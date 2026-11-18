param([Parameter(Mandatory=$true)][string]$ProjectDir)
$ErrorActionPreference = 'Stop'

function Replace-Once([string]$Path, [string]$Old, [string]$New) {
  $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n")
  if (-not $text.Contains($Old)) { throw "Expected source text not found in $Path. Pattern=[$Old]" }
  $text = $text.Replace($Old, $New)
  [System.IO.File]::WriteAllText($Path, $text, [System.Text.UTF8Encoding]::new($false))
}

$settings = Join-Path $ProjectDir 'GroupSettings.cs'
Replace-Once $settings '    public string StartUrl { get; set; } = "https://ro-idle.app/";' @'
    public string StartUrl { get; set; } = "https://ro-idle.app/";
    public bool AutoEnterCharacterBySlot { get; set; } = true;
'@

$browser = Join-Path $ProjectDir 'BrowserForm.cs'
Replace-Once $browser '    private readonly int slot;' @'
    private readonly int slot;
    private readonly bool autoEnterCharacter;
'@
Replace-Once $browser '        int slot,' @'
        int slot,
        bool autoEnterCharacter,
'@
Replace-Once $browser '        this.slot = slot;' @'
        this.slot = slot;
        this.autoEnterCharacter = autoEnterCharacter;
'@
Replace-Once $browser '        await browser.EnsureCoreWebView2Async(environment);' @'
        await browser.EnsureCoreWebView2Async(environment);
        if (autoEnterCharacter && startUri.Host.EndsWith("ro-idle.app", StringComparison.OrdinalIgnoreCase) && slot >= 1 && slot <= 4)
        {
            var slotJson = System.Text.Json.JsonSerializer.Serialize(slot);
            var script = $$"""
                (() => {
                  if (window.__mbgmAutoEnterInstalled) return;
                  window.__mbgmAutoEnterInstalled = true;
                  const targetIndex = {{slotJson}} - 1;
                  let finished = false;
                  const startedAt = Date.now();
                  const normalize = value => String(value || '').replace(/\\s+/g, '').trim();
                  const visible = el => {
                    const rect = el.getBoundingClientRect();
                    const style = window.getComputedStyle(el);
                    return rect.width > 0 && rect.height > 0 &&
                      style.display !== 'none' && style.visibility !== 'hidden' &&
                      style.opacity !== '0';
                  };
                  const tryEnter = () => {
                    if (finished || Date.now() - startedAt > 1800000) return;
                    // Game controls may be div/span elements without button attributes.
                    const matches = Array.from(document.querySelectorAll('body *')).filter(el => {
                      if (!visible(el)) return false;
                      const label = normalize(el.innerText || el.textContent || el.value ||
                        el.getAttribute('aria-label') || el.getAttribute('title'));
                      return label === '進入';
                    });
                    // Keep deepest matching text nodes; avoid counting nested wrappers repeatedly.
                    const leaves = matches.filter(el => !Array.from(el.children).some(child =>
                      visible(child) && normalize(child.innerText || child.textContent || child.value) === '進入'));
                    // Deduplicate nested nodes that occupy the same screen position.
                    const enterButtons = [];
                    for (const el of leaves) {
                      const r = el.getBoundingClientRect();
                      const duplicate = enterButtons.some(other => {
                        const q = other.getBoundingClientRect();
                        return Math.abs(r.left - q.left) < 3 && Math.abs(r.top - q.top) < 3 &&
                          Math.abs(r.width - q.width) < 3 && Math.abs(r.height - q.height) < 3;
                      });
                      if (!duplicate) enterButtons.push(el);
                    }
                    if (enterButtons.length > targetIndex) {
                      const target = enterButtons[targetIndex];
                      target.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
                      target.click();
                      finished = true;
                      console.info('[MBGM] clicked slot ' + (targetIndex + 1) +
                        '; controls=' + enterButtons.length + '; url=' + location.href);
                    } else if (Date.now() - startedAt < 15000) {
                      console.info('[MBGM] waiting slot=' + (targetIndex + 1) +
                        '; found=' + enterButtons.length + '; url=' + location.href);
                    }
                  };
                  const observer = new MutationObserver(tryEnter);
                  observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true });
                  const timer = window.setInterval(() => {
                    tryEnter();
                    if (finished || Date.now() - startedAt > 1800000) { window.clearInterval(timer); observer.disconnect(); }
                  }, 1000);
                  tryEnter();
                })();
                """;
            await browser.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(script);
            // Also install on the already-loaded document and after each navigation.
            await browser.CoreWebView2.ExecuteScriptAsync(script);
            browser.CoreWebView2.NavigationCompleted += async (_, _) =>
            {
                try { await browser.CoreWebView2.ExecuteScriptAsync(script); }
                catch { /* Navigation may have been replaced while the script was being installed. */ }
            };
            // The game may render the character list inside an iframe.
            browser.CoreWebView2.FrameCreated += (_, e) =>
            {
                try { _ = e.Frame.ExecuteScriptAsync(script); }
                catch { /* The frame may be disposed during navigation. */ }
            };
        }
'@

$manager = Join-Path $ProjectDir 'ManagerForm.cs'
Replace-Once $manager '    private readonly Label status = new();' @'
    private readonly Label status = new();
    private readonly CheckBox autoEnterCheck = new() { Text = "登入後依視窗編號自動進入角色", AutoSize = true, Margin = new Padding(8, 8, 4, 0) };
'@
Replace-Once $manager '        AddButton(top, "編輯角色名稱", EditSlotNames);' @'
        AddButton(top, "編輯角色名稱", EditSlotNames);
        AddButton(top, "修改組別名稱", RenameGroup);
'@

Replace-Once $manager '        AddButton(top, "全部關閉", StopAll);' @'
        AddButton(top, "全部關閉", StopAll);
        autoEnterCheck.Checked = settings.AutoEnterCharacterBySlot;
        autoEnterCheck.CheckedChanged += (_, _) => { settings.AutoEnterCharacterBySlot = autoEnterCheck.Checked; SaveSettings(); };
        top.Controls.Add(autoEnterCheck);
        // The toolbar previously had room for only two rows, so the checkbox
        // could be clipped below the visible area. Reserve a third row for it.
        top.AutoSize = false;
        top.Height = Math.Max(top.Height, 124);
        top.MinimumSize = new Size(0, top.Height);
        top.PerformLayout();
'@
Replace-Once $manager '                var form = new BrowserForm($"組別 {group.Name} - {slotName}", uri, env, id, slot,' @'
                var form = new BrowserForm($"組別 {group.Name} - {slotName}", uri, env, id, slot,
                    settings.AutoEnterCharacterBySlot,
'@

Replace-Once $manager '        settings.StartUrl = urlBox.Text.Trim();' @'
        settings.StartUrl = urlBox.Text.Trim();
        settings.AutoEnterCharacterBySlot = autoEnterCheck.Checked;
'@

Replace-Once $manager '    private void TileOneGroup()' @'
    private void RenameGroup()
    {
        var ids = SelectedIds();
        if (ids.Count != 1)
        {
            MessageBox.Show("請只選取一個組別，再修改名稱。");
            return;
        }
        var group = settings.Groups.FirstOrDefault(g => g.Id == ids[0]);
        if (group == null) return;

        using var dialog = new Form
        {
            Text = "修改組別名稱",
            Width = 380,
            Height = 155,
            StartPosition = FormStartPosition.CenterParent,
            FormBorderStyle = FormBorderStyle.FixedDialog,
            MaximizeBox = false,
            MinimizeBox = false
        };
        var label = new Label { Text = "組別名稱（可輸入中文）", AutoSize = true, Left = 14, Top = 16 };
        var editor = new TextBox { Left = 14, Top = 42, Width = 335, MaxLength = 24, Text = group.Name };
        var save = new Button { Text = "儲存", Left = 188, Top = 78, Width = 75, DialogResult = DialogResult.OK };
        var cancel = new Button { Text = "取消", Left = 274, Top = 78, Width = 75, DialogResult = DialogResult.Cancel };
        dialog.Controls.AddRange(new Control[] { label, editor, save, cancel });
        dialog.AcceptButton = save;
        dialog.CancelButton = cancel;
        if (dialog.ShowDialog(this) != DialogResult.OK) return;

        var newName = editor.Text.Trim();
        if (string.IsNullOrWhiteSpace(newName))
        {
            MessageBox.Show("組別名稱不能空白。");
            return;
        }
        if (settings.Groups.Any(g => g.Id != group.Id && string.Equals(g.Name, newName, StringComparison.OrdinalIgnoreCase)))
        {
            MessageBox.Show("這個組別名稱已經使用，請換一個名稱。");
            return;
        }
        group.Name = newName;
        if (running.TryGetValue(group.Id, out var forms))
            foreach (var form in forms.Where(f => !f.IsDisposed))
                form.Text = $"組別 {group.Name} - {GetSlotName(group, form.SlotNumber)}";
        SaveSettings();
        RefreshGrid();
    }

    private void TileOneGroup()
'@

Replace-Once $manager 'HeaderText = "組別編號", DataPropertyName = "Name"' 'HeaderText = "組別名稱（可自訂）", DataPropertyName = "Name"'

Write-Host 'Auto-enter and custom group-name patches applied.'

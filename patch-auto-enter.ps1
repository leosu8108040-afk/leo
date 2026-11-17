param([Parameter(Mandatory=$true)][string]$ProjectDir)
$ErrorActionPreference = 'Stop'

function Replace-Once([string]$Path, [string]$Old, [string]$New) {
  $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n")
  if (-not $text.Contains($Old)) { throw "Expected source text not found in $Path" }
  $text = $text.Replace($Old, $New)
  [System.IO.File]::WriteAllText($Path, $text, [System.Text.UTF8Encoding]::new($false))
}

$settings = Join-Path $ProjectDir 'GroupSettings.cs'
Replace-Once $settings '    public string StartUrl { get; set; } = "https://ro-idle.app/";' @'
    public string StartUrl { get; set; } = "https://ro-idle.app/";
    // 登入後依瀏覽器視窗編號，自動點選角色清單中的同順位角色。
    public bool AutoEnterCharacterBySlot { get; set; } = true;
'@

$browser = Join-Path $ProjectDir 'BrowserForm.cs'
Replace-Once $browser '    private readonly int slot;' @'
    private readonly int slot;
    private readonly bool autoEnterCharacter;
'@
Replace-Once $browser '        int slot,
        SlotWindowSettings? placement,' @'
        int slot,
        bool autoEnterCharacter,
        SlotWindowSettings? placement,
'@
Replace-Once $browser '        this.slot = slot;
        this.savePlacement = savePlacement;' @'
        this.slot = slot;
        this.autoEnterCharacter = autoEnterCharacter;
        this.savePlacement = savePlacement;
'@
Replace-Once $browser '        await browser.EnsureCoreWebView2Async(environment);
        browser.CoreWebView2.Navigate(startUri.ToString());' @'
        await browser.EnsureCoreWebView2Async(environment);
        if (autoEnterCharacter && startUri.Host.EndsWith("ro-idle.app", StringComparison.OrdinalIgnoreCase))
        {
            // 等待登入後的角色清單出現，再依此視窗的 SlotNumber 點選第 N 個「進入」。
            // 只點擊一次；找不到對應角色時不會改點其他角色。
            var slotJson = System.Text.Json.JsonSerializer.Serialize(slot);
            var script = $$"""
                (() => {
                  if (window.__mbgmAutoEnterInstalled) return;
                  window.__mbgmAutoEnterInstalled = true;
                  const targetIndex = {{slotJson}} - 1;
                  let finished = false;
                  const startedAt = Date.now();
                  const tryEnter = () => {
                    if (finished || Date.now() - startedAt > 300000) return;
                    const candidates = Array.from(document.querySelectorAll(
                      'button, [role="button"], input[type="button"], input[type="submit"]'));
                    const enterButtons = candidates.filter(el => {
                      const text = (el.innerText || el.value || el.getAttribute('aria-label') || '')
                        .replace(/\s+/g, '').trim();
                      const rect = el.getBoundingClientRect();
                      const style = window.getComputedStyle(el);
                      return text === '進入' && rect.width > 0 && rect.height > 0 &&
                        style.display !== 'none' && style.visibility !== 'hidden' && !el.disabled;
                    });
                    if (enterButtons.length > targetIndex) {
                      finished = true;
                      enterButtons[targetIndex].click();
                    }
                  };
                  const observer = new MutationObserver(tryEnter);
                  observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true });
                  const timer = window.setInterval(() => {
                    tryEnter();
                    if (finished || Date.now() - startedAt > 300000) {
                      window.clearInterval(timer);
                      observer.disconnect();
                    }
                  }, 1000);
                  tryEnter();
                })();
                """;
            await browser.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(script);
        }
        browser.CoreWebView2.Navigate(startUri.ToString());
'@

$manager = Join-Path $ProjectDir 'ManagerForm.cs'
Replace-Once $manager '    private readonly Label status = new();' @'
    private readonly Label status = new();
    private readonly CheckBox autoEnterCheck = new() { Text = "登入後依視窗編號自動進入角色", AutoSize = true, Margin = new Padding(8, 8, 4, 0) };
'@
Replace-Once $manager '        AddButton(top, "全部關閉", StopAll);' @'
        AddButton(top, "全部關閉", StopAll);
        autoEnterCheck.Checked = settings.AutoEnterCharacterBySlot;
        autoEnterCheck.CheckedChanged += (_, _) => { settings.AutoEnterCharacterBySlot = autoEnterCheck.Checked; SaveSettings(); };
        top.Controls.Add(autoEnterCheck);
'@
Replace-Once $manager '                var form = new BrowserForm($"組別 {group.Name} - {slotName}", uri, env, id, slot,
                    placement,' @'
                var form = new BrowserForm($"組別 {group.Name} - {slotName}", uri, env, id, slot,
                    settings.AutoEnterCharacterBySlot, placement,
'@
Replace-Once $manager '        settings.StartUrl = urlBox.Text.Trim();' @'
        settings.StartUrl = urlBox.Text.Trim();
        settings.AutoEnterCharacterBySlot = autoEnterCheck.Checked;
'@

Write-Host 'Auto-enter feature patch applied.'

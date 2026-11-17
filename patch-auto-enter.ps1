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
$oldCall = @'
                var form = new BrowserForm($"組別 {group.Name} - {slotName}", uri, env, id, slot,
                    placement, (slotNumber, bounds, maximized) => SaveWindowPlacement(id, slotNumber, bounds, maximized));
'@
$newCall = @'
                var form = new BrowserForm($"組別 {group.Name} - {slotName}", uri, env, id, slot,
                    settings.AutoEnterCharacterBySlot, placement,
                    (slotNumber, bounds, maximized) => SaveWindowPlacement(id, slotNumber, bounds, maximized));
'@
Replace-Once $manager $oldCall $newCall
Replace-Once $manager '        settings.StartUrl = urlBox.Text.Trim();' @'
        settings.StartUrl = urlBox.Text.Trim();
        settings.AutoEnterCharacterBySlot = autoEnterCheck.Checked;
'@

Write-Host 'Auto-enter feature patch applied.'

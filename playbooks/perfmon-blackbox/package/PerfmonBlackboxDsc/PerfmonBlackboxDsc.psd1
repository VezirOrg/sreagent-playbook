@{
    RootModule           = 'PerfmonBlackboxDsc.psm1'
    ModuleVersion        = '1.0.0'
    Author               = 'the sreagent-playbook authors'
    Copyright            = '(c) the sreagent-playbook authors. MIT licence.'
    Description          = 'DSC resources of the PerfmonBlackbox Machine Configuration package (perfmon-blackbox playbook). Not an official Microsoft product.'
    PowerShellVersion    = '5.1'
    # no empty FunctionsToExport/CmdletsToExport here: PowerShell 7.4 then hides DscResourcesToExport from
    # Get-Module -ListAvailable, and the DSC compiler (PSDesiredStateConfiguration 2.0.7) finds no resource
    DscResourcesToExport = @('BlackboxFiles', 'BlackboxCollector', 'BlackboxRunning', 'BlackboxBootTask', 'BlackboxExportTask', 'BlackboxCapacity', 'BlackboxRollTask')
}

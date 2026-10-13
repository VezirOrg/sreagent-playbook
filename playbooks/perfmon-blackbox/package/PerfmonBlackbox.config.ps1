<#
PerfmonBlackbox.config.ps1: the DSC configuration of the Machine Configuration package (design sec. 2). Compiled by
build.ps1 into PerfmonBlackbox.mof. The values below are defaults only: the policy parameters overwrite them on the
machine through the guest assignment's configurationParameter ([BlackboxFiles]Files;<Name>, decisions P23).
#>
Configuration PerfmonBlackbox {
    Import-DscResource -ModuleName PerfmonBlackboxDsc

    Node localhost {
        BlackboxFiles Files {
            Name                     = 'Files'
            MaxSizeMB                = '512'
            SampleIntervalSeconds    = '10'
            ExportEveryHours         = '4'
            StorageAccountResourceId = 'unset'
            ContainerName            = 'perfmon'
            LocalKeepMB              = '1024'
        }
        BlackboxCollector Collector {
            Name      = 'Collector'
            DependsOn = '[BlackboxFiles]Files'
        }
        BlackboxRunning Running {
            Name      = 'Running'
            DependsOn = '[BlackboxCollector]Collector'
        }
        BlackboxBootTask BootTask {
            Name      = 'BootTask'
            DependsOn = '[BlackboxFiles]Files'
        }
        BlackboxExportTask ExportTask {
            Name      = 'ExportTask'
            DependsOn = '[BlackboxFiles]Files'
        }
        BlackboxRollTask RollTask {
            Name      = 'RollTask'
            DependsOn = '[BlackboxFiles]Files'
        }
        BlackboxCapacity Capacity {
            Name      = 'Capacity'
            DependsOn = '[BlackboxRunning]Running'
        }
    }
}

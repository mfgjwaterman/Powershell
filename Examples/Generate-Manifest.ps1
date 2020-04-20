New-ModuleManifest -Path .\InstallRemoteMSI.psd1  -ModuleVersion "1.0.0.0" `
                                            -Author "Michael Waterman" `
                                            -CompanyName "MichaelWaterman.nl" `
                                            -RootModule "InstallRemoteMSI.psm1" `
                                            -Description "Install a MSI over PowerShell Remoting" `
                                            -PowerShellVersion 5.0 `
                                            -FunctionsToExport "Install-RemoteMSI"
                                            
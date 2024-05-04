#Setting variables
$State=146432
$Profiles="C:\Users\.NET v4.5", "C:\Users\.NET v4.5 Classic"

# Regex pattern for SIDs
$PatternSID = 'S-1-5-21-\d+-\d+-\d+-\d+$'
 
# Get Username, SID, and location of ntuser.dat for all users
$ProfileList = gp 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*' | Where-Object {$_.PSChildName -match $PatternSID} | 
    Select  @{name="SID";expression={$_.PSChildName}}, 
            @{name="UserHive";expression={"$($_.ProfileImagePath)\ntuser.dat"}}, 
            @{name="Username";expression={$_.ProfileImagePath -replace '^(.*[\\\/])', ''}}
 
# Get all user SIDs found in HKEY_USERS (ntuder.dat files that are loaded)
$LoadedHives = gci Registry::HKEY_USERS | ? {$_.PSChildname -match $PatternSID} | Select @{name="SID";expression={$_.PSChildName}}
 
# Get all users that are not currently logged
$UnloadedHives = Compare-Object $ProfileList.SID $LoadedHives.SID | Select @{name="SID";expression={$_.InputObject}}, UserHive, Username
 
# Loop through each profile on the machine
Foreach ($item in $ProfileList) {
    # Load User ntuser.dat if it's not already loaded
    IF ($item.SID -contains $UnloadedHives.SID) {
        reg load HKU\$($Item.SID) $($Item.UserHive) | Out-Null
    }
 
    #####################################################################
    # This is where you can read/modify a users portion of the registry 
 
    New-ItemProperty -Path "registry::HKEY_USERS\$($Item.SID)\SOFTWARE\Microsoft\Windows\CurrentVersion\WinTrust\Trust Providers\Software Publishing" -Name State -PropertyType DWord -Value $State -Force
    
    #####################################################################
 
    # Unload ntuser.dat        
    IF ($item.SID -contains $UnloadedHives.SID) {
        ### Garbage collection and closing of ntuser.dat ###
        [gc]::Collect()
        reg unload HKU\$($Item.SID) | Out-Null
    }
}


# because the .Net Accounts do not show up in the SID list, we use the trick below to set the registry keys
foreach ($item in $Profiles)
{ 
    $Checkpath = Test-Path $item

    if ($Checkpath)
    {
        #Load the User Hive
        reg.exe load HKLM\TempHive "$item\ntuser.dat" | Out-Null

        #Write the Registry Key
        New-ItemProperty -Path "registry::HKEY_LOCAL_MACHINE\TempHive\SOFTWARE\Microsoft\Windows\CurrentVersion\WinTrust\Trust Providers\Software Publishing" -Name State -PropertyType DWord -Value $State -Force
        [gc]::Collect()
       
        #Unload ntuser.dat
        reg.exe unload HKLM\TempHive | Out-Null
    }
}
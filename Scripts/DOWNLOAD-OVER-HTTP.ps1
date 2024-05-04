$url = "https://bitsofwatercom.files.wordpress.com/2017/06/native-vhd-boot-a-walkthrough-of-common-scenarios.pdf"
$output = "C:\Users\310244673\Desktop\TEST.PDF"
$start_time = Get-Date

$wc = New-Object System.Net.WebClient
$wc.DownloadFile($url, $output)
#OR
(New-Object System.Net.WebClient).DownloadFile($url, $output)

Write-Output "Time taken: $((Get-Date).Subtract($start_time).Seconds) second(s)"
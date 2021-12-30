<# 
.SYNOPSIS
    Script to monitor the removal of members of a specific group and take action.
    Schedule this script on a task scheduler server to run in incremental time

.INPUTS
    Modify the $Group and $GroupPath variable 
.OUTPUTS

.NOTES
    Author:         Alex Jaya
    Creation Date:  09/08/2021
    Modified Date:  09/10/2021

.EXAMPLE
#>

Import-Module ActiveDirectory
#This group is entitled to the Zoom app configured in Azure Enterprise applications
$Group = 'Zoom-SSOGROUP'
$GroupPath = 'GroupPath'
$Previous ="$GroupPath\PreviousMembers.csv"
$currentMembers = Get-AdGroupMember -Identity $Group -ErrorAction Stop | Select-Object samaccountname
$previousMembers = import-csv -Path $Previous | Select-Object samaccountname

#Retrieve jwt token info from encrypted files
[Byte[]] $key = (1..32)
$JWT = Get-Content '.Token.txt' | ConvertTo-SecureString -Key $key 
$JWT = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($JWT))

#Detect deleted members
$DelUsers = $previousMembers | Where-Object -FilterScript{$_.samaccountname -notin $currentMembers.samaccountname} | Select-Object -ExpandProperty samaccountname

Get-AdGroupMember -Identity $Group | Select-Object samaccountname | Export-Csv -Path $Previous -Encoding UTF8 -NoTypeInformation

if($DelUsers){
    foreach($user in $DelUsers){
        try{
            $useremail = Get-ADUser $user -Properties mail| Select-Object -ExpandProperty mail 
            $URIPath = 'https://api.zoom.us/v2/users/' + $useremail + '?action=delete&transfer_email=false&transfer_meeting=false&transfer_webinar=false&transfer_recording=false'
            $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
            $headers.Add("Authorization", "Bearer " + $JWT)
            $headers.Add("Cookie", "_zm_chtaid=512; _zm_ctaid=xPjTAIlyTxSe-pqn2zuBKQ.1631301615741.1efbe65038951145c5539e16f6790116; _zm_page_auth=aw1_c_QLA1qa-5QmyOU09fNPBAWg; _zm_ssid=aw1_c_l-OwS9OnT1KUa16xF3Ihhw; cred=8A4384A7BB47F38F19E83CF4651D11C1")
            
            $response = Invoke-RestMethod $URIPath -Method 'DELETE' -Headers $headers
            $response | ConvertTo-Json
        }Catch{}        
    }
}
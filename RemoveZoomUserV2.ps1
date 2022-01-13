<# 
.SYNOPSIS
    Pull a list of all users from Zoom and compare them with 
    the group that's assigned to the azure sso app.  If they don't exists in the group, then remove from zoom platform.

.INPUTS
    Modify the $Group and $GroupPath variable 
.OUTPUTS


.NOTES
    Author:         Alex Jaya
    Creation Date:  1/12/2022
    Modified Date: 

.EXAMPLE
#>

Import-Module ActiveDirectory
#This group is entitled to the Zoom app configured in Azure Enterprise applications
$Group = 'Zoom-SSOGROUP'
$GroupPath = 'GroupPath'
$GroupDNs = get-adgroup -identity $Group -Properties Member | Select-Object -Property 'Member' -ExpandProperty 'Member'
$currentMembers = foreach($GroupDN in $GroupDNs){
    get-aduser -filter * -SearchBase $GroupDN -Properties name,samaccountname,mail | select name,samaccountname,mail
}

#Retrieve jwt token info from encrypted files
[Byte[]] $key = (1..32)
$JWT = Get-Content '.Token.txt' | ConvertTo-SecureString -Key $key 
$JWT = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($JWT))

#Get a list of all users from zoom platform
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Authorization", "Bearer " + $JWT)
$headers.Add("Cookie", "cred=65B2C4B656BF56E37090F6452046A225")
$response = Invoke-RestMethod 'https://api.zoom.us/v2/users?page_size=1000&login_type=101&encrypted_email=false' -Method 'GET' -Headers $headers
$response | ConvertTo-Json

#Loop through and paginate through the returned pages
$PageCount = $response.page_count
for($i=1; $i -le $PageCount;$i++){
    $next_page = $response.next_page_token
    $response = Invoke-RestMethod "https://api.zoom.us/v2/users?page_size=300&login_type=101&encrypted_email=false&next_page_token=$next_page" -Method 'GET' -Headers $headers
    #write-host $next_page
    $ZoomUsers += $response.users | Select-Object first_name,last_name,email,status
}

$ZoomADUsers = foreach($user in $ZoomUsers){
                    $email = $user.email
                    Get-ADUser -Filter {EmailAddress -eq $email} -Properties samaccountname,mail | Select-Object samaccountname,mail
                }
                
#Detect deleted members
Clear-Variable ZoomUsers
#Detect deleted members
$DelUsers = $ZoomADUsers | Where-Object -FilterScript{$_.samaccountname -notin $currentMembers.samaccountname} | Select-Object -ExpandProperty mail

if($DelUsers){
    foreach($user in $DelUsers){
        try{
            $useremail = $user
            $URIPath = "https://api.zoom.us/v2/users/$useremail/status"
            $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
            $headers.Add("Authorization", "Bearer " + $JWT)
            $headers.Add("Content-Type", "application/json")
            $headers.Add("Cookie", "cred=07535293F633173BE1BD3398F456BF6A")

            $body = "{
            `n  `"action`": `"deactivate`"
            `n}"

            $response = Invoke-RestMethod $URIPath -Method 'PUT' -Headers $headers -Body $body
            $response | ConvertTo-Json
        }Catch{}
    }
}

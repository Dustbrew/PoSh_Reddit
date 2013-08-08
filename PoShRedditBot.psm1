$Global:BaseUrl = "http://www.reddit.com"
$Global:UserAgent = "User-Agent PoShBot/1.0 Beta by Davotronic5000"
$Global:ApiType = "json"

#region Connect-Reddit

<# 
.SYNOPSIS
Function to connect to reddit and creat a global session, to allow other reddit commands to be authenticated

.DESCRIPTION
Connects to reddit with supplied credentials and authenticates to collect a modhash and session data.

.PARAMETER  Credential
Credentials to connect to reddit, accepts PSCredential object

.PARAMETER Remember
Boolean parameter sets if Session data should be persisitant

.EXAMPLE
Connect-Reddit -Credential "PoShBot" -Remember $True

.INPUTS
None

.OUTPUTS
$GLobal:Session - Reddit Session data
$Global:ModHash - Reddit API modhash
.NOTES
Created By: Dave Garnar/Davotronic5000

.LINK
http://davotronic5000.co.uk/blog
http://reddit.com/r/PowerShell
#>

FUNCTION Connect-Reddit
    {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="Medium")] 
    PARAM
        (
        [parameter(Mandatory=$true)]
        [Alias("Username","Cred")]
      	[System.Management.Automation.PSCredential]
      	[System.Management.Automation.Credential()]$Credential =  [System.Management.Automation.PSCredential]::Empty,
        
        [PSDefaultValue(Help = "True")]
        $Remember = $True
        )

    $Params = @{
    "api_type" = $Global:ApiType
    "passwd" = $Credential.GetNetworkCredential().Password
    "rem" = $Remember
    "user" = $Credential.UserName
    }
    IF ($psCmdlet.ShouldProcess($Global:BaseUrl, "Connecting with Username $($Credential.UserName)"))
        {
        TRY
            {
            Write-Verbose "Logging in to Reddit"
            $Login = Invoke-WebRequest -uri "$Global:BaseUrl/api/login" -Method Post -Body $Params -SessionVariable Global:Session -UserAgent $Global:UserAgent | ConvertFrom-Json
            }
        Catch
            {
            Write-Error -RecommendedAction Stop -Message "Unable to connect to Reddit" -Exception $_.Exception.Message
            }

        IF ($Login.json.data.modhash -and $Global:Session.Cookies.count -gt 0)
            {
            Write-Verbose "Successfully logged in to reddit"
            $Global:ModHash = $Login.json.data.modhash
            }
        ELSEIF ($Login.json.errors -like "*WRONG_PASSWORD*")
            {
            Write-Error -RecommendedAction Stop -Message "Incorrect Username or Password, please re-run the command with the correct details"
            }
        ELSEIF ($login.json.errors -like "*RATELIMIT*")
            {
            Write-Error -RecommendedAction Stop -Message "$($login.json.errors)"
            }
        }
    }
#endregion

#region Submit-Post

<# 
.SYNOPSIS
Submits a post to your chosen subereddit

.DESCRIPTION
function to subint a link or self post to yuor chosen subreddit

.PARAMETER  PostType
Whether post is a link or self post

.PARAMETER Resubmit
Whether a link post should be resubmitted if it has been posted previously

.PARAMETER SavePost
Should post be saved to your profile saved list

.PARAMETER SubReddit
Which subreddit the post will be submitted to

.PARAMETER PostBody
The body text if the post is a self post

.PARAMETER PostTitle
The title of the submitted post

.PARAMETER PostLink
If the post is a link post, this specifys the link.

.PARAMETER FailOnCaptcha
Function will not pause for user input on captcha, the post will just fail to submit

.EXAMPLE
Submit-Post -PostType self -SubReddit "PowerShell" -PostBody "Test Message" -PostTitle "Test Post"

.Example
Submit-Post -PostType link -SubReddit "PowerShell" -PostLink "http://www.powershell.org" -ReSubmit $True

.INPUTS


.OUTPUTS

.NOTES
Created By: Dave Garnar/Davotronic5000

.LINK
http://davotronic5000.co.uk/blog
http://reddit.com/r/PowerShell
#>

FUNCTION Submit-Post
    {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="Medium")]
    PARAM
        (
        [parameter(Mandatory=$true)]
        [ValidateSet("self", "link")]
        [STRING]$PostType,

        [parameter(ParameterSetName="Link")]
        [PSDefaultValue(Help = 'False')]
        [BOOL]$Resubmit = $False,

        [BOOL]$SavePost,

        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [PSDefaultValue(Help = 'PowerShell')]
        [STRING]$SubReddit = "PowerShell",

        [parameter(Mandatory=$true, ParameterSetName="Self")]
        [ValidateNotNullOrEmpty()]
        [STRING]$PostBody,

        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [STRING]$PostTitle,

        [parameter(Mandatory=$true, ParameterSetName="Link")]
        [ValidateNotNullOrEmpty()]
        [STRING]$PostLink,

        [PSDefaultValue(Help = 'False')]
        [BOOL]$FailOnCaptcha = $False
        )

    $params = @{
    "api_type" = $Global:ApiType
    "kind" = $PostType
    "resubmit" = $Resubmit
    "save" = $SavePost
    "extension" = "json"
    "sr" = $SubReddit
    "text" = $PostBody
    "title" = $PostTitle
    "uh" = $Global:Modhash
    "url" = $PostLink
    }

#add a default footer to posts made by the bot
    $PostBody = @"
$PostBody
---
This is an automated post submitted by PoShBot a reddit bot written in PowerShell by /u/Davotronic5000.
"@



    IF ($psCmdlet.ShouldProcess("## object ##", "## message ##"))
        {
        TRY
            {
            $Submit = Invoke-WebRequest -uri "$Global:BaseUrl/api/submit" -Method Post -Body $Params -WebSession $GLOBAL:Session -UserAgent $Global:UserAgent | ConvertFrom-Json
            }
        CATCH
            {
            Write-Error -RecommendedAction Stop -Message "Failed to submit the post to Reddit" -Exception $_.Exception.Message
            }

        IF ($Submit.json.Data)
            {
            Write-Verbose "Post successfully submitted to reddit"
            Write-Output $Submit
            }
        # If post failed because of captcha, check if fail on captcha is set to false
        ELSEIF ($Submit.json.errors -like "*BAD_CAPTCHA*")
            {
            IF (!$FailOnCaptcha)
                {
                #If fail on captcha is false request manual intervention to complete
                $Captcha = Resolve-Captcha -CaptchaIden $Submit.json.captcha
                $Params += @{
                "captcha" = $Captcha.Answer
                "iden" = $Captcha.Iden
                }
                $SubmitWithCaptcha = Invoke-WebRequest -uri "$Global:BaseUrl/api/submit" -Method Post -Body $Params -WebSession $GLOBAL:Session -UserAgent $Global:UserAgent | ConvertFrom-Json
                Write-Output $SubmitWithCaptcha
                }
            }
        }

    }
#endregion

#region Resolve-Captcha
<# 
.SYNOPSIS
Solves a captcha

.DESCRIPTION
Function to prompt for user input to solve a captcha when required by the API

.PARAMETER  CaptchaIden
ID of the required captcha, accepts pipeine input

.EXAMPLE
Resolve-Captcha -CaptchIden "BRxX7YD9ysKxUnlvWVMYSFoPjZoeacUN"

.INPUTS
None

.OUTPUTS
Outputs object with captcha Iden and Captcha answer

.NOTES
Created By: Dave Garnar/Davotronic5000

.LINK
http://davotronic5000.co.uk/blog
http://reddit.com/r/PowerShell
#>

FUNCTION Resolve-Captcha
    {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="Medium")]
    PARAM
        (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [String]$CaptchaIden
        )
    Write-Verbose "Create Captch URL and copy to clipboard"
    $Captcha = "$Global:BaseUrl/captcha/$CaptchaIden"
    $Captcha | CLip

    IF ($psCmdlet.ShouldProcess($CaptchaIden, "Prompting for soution of Captcha"))
        {
        #Prompt user to answer captcha
        $CaptchaAnswer = Read-Host "Please go to $Captcha in a browser and enter the captcha text here (the link has already been placed in your clipboard):"

        Write-Verbose "Outputting Captcha data"
        $output = [ORDERED] @{
        "Iden" = $CaptchaIden
        "Answer" = $CaptchaAnswer
        }
    }
    New-Object PSObject -Property $Output

    }
#endregion

#region Help-Template

<# 
.SYNOPSIS


.DESCRIPTION


.PARAMETER  Credential


.PARAMETER Remember


.EXAMPLE


.INPUTS


.OUTPUTS

.NOTES
Created By: Dave Garnar/Davotronic5000

.LINK
http://davotronic5000.co.uk/blog
http://reddit.com/r/PowerShell
#>

#endregion
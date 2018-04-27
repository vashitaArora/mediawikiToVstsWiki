param(
    [Parameter(Mandatory=$True, HelpMessage="Your media wiki url <format: http://localhost:8080/mediawiki>")]
    [string]$mu, 
    [Parameter(Mandatory=$True, HelpMessage="Your image backup location <format: C:\xampp\htdocs\mediawiki\images>")]
    [string]$ip, 
    [Parameter(Mandatory=$True, HelpMessage="mediawiki username <format: alias>" )]
    [string]$u,
    [Parameter(Mandatory=$True, HelpMessage="mediawiki password")]
    [SecureString]$pwd,
    [Parameter(Mandatory=$False, HelpMessage="mediawiki absolute url(can be different from mediawiki url provided above - to change absolute urls in content) <format: https://mywiki.com/index.php\?title=>")] 
    [string]$au , 
    [Parameter(Mandatory=$False, HelpMessage="updated mailto string")]
    [string]$mt = '@microsoft.com', 
    [Parameter(Mandatory=$True, HelpMessage="output directory on disk <format: C:\anylocation\>")]
    [string]$o,
    [Parameter(Mandatory=$True, HelpMessage="vsts wiki clone url <format: https://myacct.visualstudio.com/proj/_git/proj.wiki>")]
    [string]$r,
    [Parameter(Mandatory=$False, HelpMessage="vsts username (Please provide PAT token if asked for password)")]
    [string]$vstsUserName,
    [Parameter(Mandatory=$True, HelpMessage="path where pandoc.exe resides <format: C:\pandoc\>")]
    [string]$pnPath
    )

#input
$mediaWikiCoreUrl = $mu + '/api.php?format=json&' #'http://localhost:8080/mediawiki1'
$mediaWikiImageBackupPath = $ip 
$mailToOrg = $mt #'@microsoft.com'
$mediaWikiUrl = $au 

$userName = $u
$password = ConvertTo-SecureString $pwd -AsPlainText -Force

$vstsWikiPATtoken = $c #""
$vstsWikiRemoteUrl = $r
$wikiName = $vstsWikiRemoteUrl|split-path -leaf
$rootPath = $o
$localMachinePath = $o + $wikiName + '\' 
$patToken = $pat
$pandocPAth = $pnPath 

#local
$mediaWikiGetAllCatgoriesPartialUrl = 'list=allcategories&action=query&aclimit=500&'
$mediaWikiAllCategoriesContinuationToken = 'accontinue'
$mediaWikiAllCategoriesContinuationTokenValue = ''
$mediaWikiAllCategoriesTitleArray =  New-Object System.Collections.Generic.List[System.Object]
$currentCategoryElement = '*'

$mediaWikiCategoryPrefix = 'Category'
$mediaWikiCategoryContentPartialUrl = 'action=query&prop=revisions&rvprop=content&titles='

$mediaWikiPageContentPartialUrl = 'action=query&prop=revisions&rvprop=content&titles='
$mediaWikiCategoryContentFullUrl = $vsoWikiCoreUrl + $vsoWikiCategoryContentPartialUrl

$mediaWikiGetAllPagesPartialUrl = 'action=query&list=allpages&aplimit=500&'
$mediaWikiAllPagesContinuationToken = 'apcontinue'
$mediaWikiAllPagesContinuationTokenValue = ''
$mediaWikiAllPagesTitleArray =  New-Object System.Collections.Generic.List[System.Object]

$mediaWikiGeBackLinksPartialUrl = 'action=query&list=backlinks&bllimit=500&bltitle='
$mediaWikiGeBackLinksPartialContinuationToken = 'blcontinue'

$attachmentFolderName = '.attachments'
$attachmentFolderPath = $localMachinePath + $attachmentFolderName + '\'
$mediaWikiAllImagesArray =  New-Object System.Collections.Generic.List[System.Object]

$mediaWikiPageNamesContainingSlash =  New-Object System.Collections.Generic.List[System.Object]


$uniqueNameashTable = New-Object Hashtable

$duplicatePageNames =  New-Object System.Collections.Generic.List[System.Object]

$renamedItems = New-Object Hashtable
$renamedItems1 = New-Object Hashtable
$oldPageNameToNewHashTable = New-Object Hashtable
$websession = $null
####BEGIN####


function Get-WebSession()
{
    
    if($websession -eq $null)
    {
        Invoke-LogIn $userName $password
    }
    return $websession
}

function Invoke-Login($username, $password)
{
    $uri = $mediaWikiCoreUrl

    $body = @{}
    $body.action = 'login'
    $body.format = 'json'
    $body.lgname = $username
    $body.lgpassword = $password


    $object = Invoke-WebRequest $uri -Method Post -Body $body -SessionVariable global:websession
    Write-Host 'here'
    $json = $object.Content
    $object = ConvertFrom-Json $json
    
    if($object.login.result -eq 'NeedToken')
    {
        $uri = $mediaWikiCoreUrl
        
        $body.action = 'login'
        $body.format = 'json'
        $body.lgname = $username
        $body.lgpassword = $password
        $body.lgtoken = $object.login.token

        $object = Invoke-WebRequest $uri -Method Post -Body $body -WebSession $global:websession
        $json = $object.Content
        $object = ConvertFrom-Json $json
    }
    if($object.login.result -ne 'Success')
    {
        # throw ('Login.result = ' + $object.login.result)
    }
}

#########################Attachments################################################
function getAllImages() {
    $mediaWikiAllImagesArray = get-childitem $mediaWikiImageBackupPath -rec | where {!$_.PSIsContainer} | select-object FullName 

    New-Item -ItemType Directory -Force -Path $attachmentFolderPath

    ForEach($image in $mediaWikiAllImagesArray) {

        $imagePath = $image.FullName

        copy-item -path $imagePath -destination $attachmentFolderPath

    }
}
##################################################################################

########################Pages######################################################

function formatPageNameInLinks($pageName) {
    If($pageName.StartsWith('http://') -or $pageName.StartsWith('https://')) {
        return $pageName
    }

    $pageName = $pageName.TrimStart(':'); 

    $pageName = $pageName.Replace('-','%2D')
    $pageName = $pageName.Replace('_','-')
    $pageName = replaceDisallowedCharacters($pageName)

    return $pageName
    
}

function createPageHierarchy() {
    #for now return flat hierarchy
    getAllCategories  #$mediaWikiAllCategoriesTitleArray
    getAllPages  #mediaWikiAllPagesTitleArray
    getAllItemsNameAndHierarchy #oldPageNameToNewHashTable
}

function getAllCategories() {
    # Get all categories
    do {
        $mediaWikiGetAllCatgoriesFullUrl = $mediaWikiCoreUrl + $mediaWikiGetAllCatgoriesPartialUrl + $mediaWikiAllCategoriesContinuationToken + '=' + $mediaWikiAllCategoriesContinuationTokenValue
        $res = Invoke-WebRequest -Uri $mediaWikiGetAllCatgoriesFullUrl -WebSession (Get-WebSession)| ConvertFrom-Json

        If($res.query) {
            # new continuation token
            if($res.continue) {
                $mediaWikiAllCategoriesContinuationTokenValue = $res.continue.$mediaWikiAllCategoriesContinuationToken
            } else {
                $mediaWikiAllCategoriesContinuationTokenValue = ''
            }
            # add name to all category array
            ForEach($child in $res.query.allcategories) {
                $title = $child.psobject.properties.value
                $mediaWikiAllCategoriesTitleArray.Add($mediaWikiCategoryPrefix + ':' +$title)

                if($title.Contains('\')) {
                    $mediaWikiPageNamesContainingSlash.Add($title)
                }
            }
        }
    } while ($mediaWikiAllCategoriesContinuationTokenValue -ne '')
    
    $mediaWikiAllCategoriesTitleArray.ToArray();
}

function getAllPages($Headers) {
    # Get all categories
    do {
        $mediaWikiGetAllPagesFullUrl = $mediaWikiCoreUrl + $mediaWikiGetAllPagesPartialUrl + $mediaWikiAllPagesContinuationToken + '=' + $mediaWikiAllPagesContinuationTokenValue
        
        $res = Invoke-WebRequest -Uri $mediaWikiGetAllPagesFullUrl -WebSession (Get-WebSession)| ConvertFrom-Json

        If($res.query) {
            # new continuation token
            
            if($res.continue) {
                $mediaWikiAllPagesContinuationTokenValue = $res.continue.$mediaWikiAllPagesContinuationToken
            } else {
                $mediaWikiAllPagesContinuationTokenValue = ''
            }
            
            # add name to all category array
            ForEach($child in $res.query.allpages) {
                $title = $child.title.Trim('\"')
                
                if($uniqueNameashTable[$title.ToLower()]) {
                    # if a file with this name already exists - dont process
                    $duplicatePageNames.Add($title) #TODO do this for categories as well
                } else {
                    $uniqueNameashTable.Add($title.ToLower(), $true)
                    $mediaWikiAllPagesTitleArray.Add($title)
                }

                if($title.Contains('\')) {
                    $mediaWikiPageNamesContainingSlash.Add($title)
                }

                
            }
        }
    } while ($mediaWikiAllPagesContinuationTokenValue -ne '')


    $mediaWikiAllPagesTitleArray.ToArray();
}

function replaceSpace($pathName) {
    $pathName = $pathName.Replace(' ','-')

    return $pathName
}

function reverseReplaceSpace($pathName) {
    $pathName = $pathName.Replace('-', ' ')

    return $pathName
}

function replaceSpecialCharacters($pathName) {

    #Encoded
    $pathName = $pathName.Replace(':','%3A')
    $pathName = $pathName.Replace('>','%3E')
    $pathName = $pathName.Replace('-','%2D')
    $pathName = $pathName.Replace('<','%3C')
    $pathName = $pathName.Replace('|','%7C')
    $pathName = $pathName.Replace('?','%3F')
    $pathName = $pathName.Replace('"','%22')
    $pathName = $pathName.Replace('*','%2A')

    return $pathName
}

function reverseReplaceSpecialCharacters($pathName) {

    #Encoded
    $pathName = $pathName.Replace('%3A',':')
    $pathName = $pathName.Replace('%3E','>')
    $pathName = $pathName.Replace('%2D','-')
    $pathName = $pathName.Replace('%3C', '<')
    $pathName = $pathName.Replace('%7C','|')
    $pathName = $pathName.Replace('%3F', '?')
    $pathName = $pathName.Replace('%22','"')
    $pathName = $pathName.Replace('%2A', '*')

    return $pathName
}

function replaceDisallowedCharacters($pathName) {

    $pathName = $pathName.Replace('/','_')
    #$pathName = $pathName.Replace('\','_')
    #$pathName = $pathName.Replace('#','_')

    return $pathName
}

function reverseReplaceDisallowedCharacters($pathName) {

    $pathName = $pathName.Replace('_','/')
    #$pathName = $pathName.Replace('\','_')
    #$pathName = $pathName.Replace('#','_')

    return $pathName
}
function formatPageName($pathName) {
    $pathName = replaceSpecialCharacters($pathName)
    $pathName = replaceDisallowedCharacters($pathName)
    $pathName = replaceSpace($pathName)

    return $pathName
}

function reverseFormatPageName($pathName) {
    
    
    $pathName = reverseReplaceSpace($pathName)
    $pathName = reverseReplaceDisallowedCharacters($pathName)
    $pathName = reverseReplaceSpecialCharacters($pathName)

    return $pathName
}

function getAllItemsNameAndHierarchy() {
    $allItems = $mediaWikiAllPagesTitleArray + $mediaWikiAllCategoriesTitleArray
    ForEach($item in $allItems) {

        $urlencodedPageName = formatPageName($item)
        $urlencodedPageName = $urlencodedPageName.Replace('\', '%5C')
        $fileName = $localMachinePath + $urlencodedPageName + '.md'
        #Write-Host 'adding-'$item ':'$fileName
        $oldPageNameToNewHashTable.Add($item, $fileName)  
    }
}



function getCurrentPage ($itemOriginalName) {
    $mediaWikiPageContentFullUrl = $mediaWikiCoreUrl + $mediaWikiPageContentPartialUrl + $itemOriginalName

    $res = Invoke-WebRequest -Uri $mediaWikiPageContentFullUrl -WebSession (Get-WebSession)| ConvertFrom-Json
    $isMissing = $res.query.pages.psobject.properties.value.missing -eq ''
    $content = ''

    if($isMissing -eq $false) {
        # Get Page Content
        $content = $res.query.pages.psobject.properties.value.revisions[0].'*'
    }

    return $content
}

function getPageContent() {
    
    $currentCount = 1
    $totalCount = $oldPageNameToNewHashTable.Count

    Foreach ($key in @($oldPageNameToNewHashTable.Keys)) {

        $path = $oldPageNameToNewHashTable[$key]
        $itemOriginalName = $key
        $itemFinalName = [System.IO.Path]::GetFileNameWithoutExtension($path)

        Write-Host '****************************************************************************'
        Write-Host 'Fetching ' $currentCount ' of ' $totalCount ': ' $itemOriginalName '| Final name: ' $path
        $currentCount++

        $content = getCurrentPage $itemOriginalName 

        If($content -eq $null -or $content.Trim(' ') -eq '') {
            #dont create this file
            #make null entry for this item in oldPageNameToNewHashTable
            Write-Host 'missing case'
            $oldPageNameToNewHashTable.Remove($key)

        }

        #for non-category items, remove redirect only links
        ElseIf($itemOriginalName.StartsWith('Category:') -eq $false -and $content.TrimStart(' ').StartsWith('#REDIRECT')) {
            #if content starts with REDIRECT ignore it
            $renamedPathArr = $content -split '\s*#REDIRECT\s*\[\[(.*)\]\]'
            $renamedName  = $renamedPathArr[1].Replace('_',' ')

            $renamedItems.Add($itemOriginalName, $renamedName)
            $oldPageNameToNewHashTable.Remove($key) # pick this from renamed list only to avoid confusion
        }
        Else {
            # create this file
            New-Item -ItemType file -Force -Path $path
            [System.IO.File]::WriteAllLines($path, $content)
        }

    }

    Write-Host 'FINISHED WITH '$oldPageNameToNewHashTable.Count
}

#########################Preprocess################################

function isLineCodeBlock($line) {
    # images and url are not supported inside code blocks
    #$hasImageText = $line.ToLower().Contains('[[file:')
    If($line -eq $null) {
        return $false
    }

    $hasUrlOrImageText = $line.Contains('[[')
    $isCodeBlock = $line.StartsWith(' ') -and $line.Trim(' ') -ne '' -and $hasUrlOrImageText -eq $false

    return $isCodeBlock
}



function preProcessCurrentPage($content) {
    ## replace [[http...]] with [http...]
    $content = $content -replace '(\[\[http)(((?!\]\]).)*)(\]\])','[http$2]'
    $content = $content -replace '(\[\[file:)(((?!\]\]).)*)(\]\])','[[File:$2]]'
    #vso wiki only
    $content = $content -replace '\|framed\|','|frame|'
    $content = ParseLineByLine $content
    $content = handleMailToBlocks($content)


    return $content
}

function handleMailToBlocks($content) {
    If($mailToOrg -ne '') {
        $regexStr = '(\[mailto:)(((?!' + $mailToOrg + '|\]|\s).)*)\s+([^\]]*)\]'
        $replaceStr = '[mailto:$2' + $mailToOrg +  ' $4]'
        return $content -replace $regexStr, $replaceStr
    }

    return $content
}

function ParseLineByLine($content) {
    #$content = $content -replace '<br/>|<br />', '' # see if this can be \n 
    $result = $content -split "`n"
    $count = 0;
    $thisFile = $false
    $prevLine = ''
    $codeBlockStart = -1

    For($i = 0; $i -lt $result.Count; $i++) {
        $line = $result[$i]

        $count++
        If($line -ne $null) {
            If($line.Contains('<pre') ) {
                $codeBlockStart = $i
                #ignore everything until you see </pre>
                While($line -ne $null -and ($line.Contains('</pre>') -eq $false) -and ($i -lt $result.Count)) {
                    #Write-Host 'ignoring' $line 
                    $i++
                    $line = $result[$i]
                
                }
                $codeBlockStart = -1
            }
            ElseIf($line.Contains('{| class="wikitable" ') ) {
                $codeBlockStart = $i
                #ignore everything until you see </pre>
                While($line -ne $null -and ($line -ne '|}') -and ($i -lt $result.Count)) {
                    #Write-Host 'ignoring' $line 
                    $result[$i] = $result[$i].TrimStart(' ')
                    $i++
                
                    $line = $result[$i]
                
                }
                $codeBlockStart = -1
            }
            ElseIf($line.Contains('<code') ) {
                $codeBlockStart = $i
                #ignore everything until you see </pre>
                While($line -ne $null -and ($line.Contains('</code>') -eq $false) -and ($i -lt $result.Count)) {
                    $i++
                    $line = $result[$i]
                    #Write-Host 'ignoring'
                }
                $codeBlockStart = -1
            }
            ElseIf($line.Contains('<source') ) {
                $codeBlockStart = $i
                #ignore everything until you see </pre>
                While($line -ne $null -and ($line.Contains('</source>') -eq $false) -and ($i -lt $result.Count)) {
                    $i++
                    $line = $result[$i]
                    #Write-Host 'ignoring'
                }
                $codeBlockStart = -1
            }
            ElseIf($line.Contains('<syntaxhighlight') ) {
                $codeBlockStart = $i
                #ignore everything until you see </pre>
                While($line -ne $null -and ($line.Contains('</syntaxhighlight>') -eq $false) -and ($i -lt $result.Count)) {
                    $i++
                    $line = $result[$i]
                    #Write-Host 'ignoring'
                }
                $codeBlockStart = -1
            }
            ElseIf(isLineCodeBlock $line) {
                if($codeBlockStart -eq -1) {
                    $codeBlockStart = $i
                    #$result[$i] = '<pre>' + $result[$i]
                }
            }
            Else{
                $result[$i] = $result[$i] -replace '<br/>|<br />', '' # see if this can be \n 
                If($codeBlockStart -ne -1) {

                    if($codeBlockStart -eq ($i-1)) {
                        if($result[$i-1].Trim(' ') -ne '') {
                            $result[$i-1] = '<pre>' + $result[$i-1] + '</pre>'
                        }
                    }
                    Else {
                        $result[$codeBlockStart] = '<pre>' + $result[$codeBlockStart]
                        $result[$i-1] = $result[$i-1] + '</pre>'
                    }
                    $codeBlockStart = -1
                }
            }
            #Write-Host $line
            If($line -ne $null) {
                If($line.StartsWith(':')) {
                     $result[$i] = $result[$i].TrimStart(':') #remove ':' as pandoc is unable to understand it
                     $result[$i] = $result[$i].TrimStart(' ')

                }
                If($line.Contains('{{table}}')) {
                    $result[$i] = $result[$i] -replace '{{table}}', ''
                }
                If($line.Contains('|-|}') ) {
                    $result[$i] = $result[$i] -replace '|}', ''
                }

             
            }
        }

    }

    If($codeBlockStart -ne -1) {
            if($codeBlockStart -eq ($i-1)) {
                if($result[$i-1].Trim(' ') -ne '') {
                    $result[$i-1] = '<pre>' + $result[$i-1] + '</pre>'
                }
            }
            Else {
                $result[$codeBlockStart] = '<pre>' + $result[$codeBlockStart]
                $result[$i-1] = $result[$i-1] + '</pre>'
            }
            $codeBlockStart = -1
        }

    $newContent = $result -join "`n"

    return $newContent
}

function preProcessPages () {
    Foreach ($key in @($oldPageNameToNewHashTable.Keys)) {
        Write-Host 'preProcessing : ' $key
        $path = $oldPageNameToNewHashTable[$key]
        #Write-Host $path
        $content = Get-Content $path -Raw
        $content = preProcessCurrentPage $content
        Set-Content -Path $path -Value $content
    }
}
###############################################################################

###################Processign#####################################################
function processPages() {
    Foreach ($key in @($oldPageNameToNewHashTable.Keys)) {
            $path = $oldPageNameToNewHashTable[$key]
            Write-Host 'Processing : ' $key
            $pandocCommand = $pandocPAth + 'pandoc.exe' 
            & $pandocCommand  $path --from=mediawiki --to=gfm  -o $path --eol=native --wrap=preserve
        }
}
##################################################################################

###################Post-Processing################################################

function convertImagesForCurrentPage($newContent) {
        ########################## replace image content###########################
        # inline-style 
        # what if it is an absolute path : media wiki seems to not support absolute image paths
        # what about extension : already present
        $newContent = $newContent -replace '(!\[)([^\]]*)(\])(\()(((?!https:\/\/|http:\/\/|\)).)*)(\))', '![$2](.attachments\$5)'

        return $newContent
}

function convertAbsoluteMediWikiUrl($content) {
    #######################replace links#######################################
    # inline-style 
    # [](..."wikilinks")  
    If($mediaWikiUrl -eq '' -or $mediaWikiUrl -eq $null) {
        return $content
    }
    
    $regexUrl = '<'+$mediaWikiUrl + '([^\)]*)>' 
    $newContent = $newContent -replace $regexUrl, '[$1]($1"wikilink")'
    $regexUrl = '(\[)([^\]]*)(\])\('+ $mediaWikiUrl + '([^\)]*)\)' 
    $newContent = $newContent -replace $regexUrl, '[$2]($4"wikilink")'

    return $newContent
}

function convertWikiLinks($content) {
    $parts = $content -split '(\[)([^\]]*)(\])(\()(((?!wikilink|https:\/\/|http:\/\/).)*)"wikilink"(\))'

    $pos = 0
    $nextMatchingPos = -1
    $nextIgnoredGroup = -1
    $newContent = ''

    while($pos -lt $parts.Length) {

        if($pos -eq $nextMatchingPos) {
            $parts[$pos] = formatPageNameInLinks $parts[$pos]
           
        }
        # Look for next occurance of [
        if($parts[$pos] -eq "[") {
           # Write-Host 'Found ['
            $nextMatchingPos = $pos + 4
            $nextIgnoredGroup = $pos + 5
        }
    

        if($pos -ne $nextIgnoredGroup) {
            $newContent += $parts[$pos]
        }
        $pos++
    }

    return $newContent
}

function convertUrlsForCurrentPage($newContent) {
    
    $newContent = convertAbsoluteMediWikiUrl($newContent)
    $newContent = convertWikiLinks($newContent)
    ###########################################################################

    # [][]
    ###########################################################################
    return $newContent
}

function handleUNCPath($content) {
    return $content -replace "(<file>)(.+?)(</file>)",'**$2**'
}

function postProcessPage($path) {
    $content = Get-Content $path -Raw
    $content = convertImagesForCurrentPage($content)
    $content = convertUrlsForCurrentPage($content)
    $content = handleUNCPath($content)

    return $content
}

function postProcessPages() {
    Foreach ($key in @($oldPageNameToNewHashTable.Keys)) {
            $path = $oldPageNameToNewHashTable[$key]
            Write-Host 'postProcessing : ' $key
            $content = postProcessPage($path)
               
            Set-Content -Path $path -Value $content
        }
}

##################################################################################

########################SpecialPAges############################################

function getAlterNateFilePath($pathName) {
    
    $counter = 1
    $newPathName = $localMachinePath + $pathName + '.md'
    while(Test-Path $newPathName) {
        $counter++
        $newPathName = $localMachinePath + $pathName + '(' + $counter + ')' + '.md'
    }

    #Write-Host 'New path: ' $newPathName
    return $newPathName
    
}

function handleSpecialPages() {
    # Duplicate page names
    ForEach($pageWithDuplicateName in $duplicatePageNames) {
        $content = getCurrentPage $pageWithDuplicateName, $Header
        
        If($content -eq $null -or $content.Trim(' ') -eq '') {
                $renamedItems.Add($pageWithDuplicateName, $null)
            }
            ElseIf($pageWithDuplicateName.StartsWith('Category:') -eq $false -and $content.TrimStart(' ').StartsWith('#REDIRECT')) {
                $renamedPathArr = $content -split '\s*#REDIRECT\s*\[\[(.*)\]\]'
                $renamedName  = $renamedPathArr[1].Replace('_', ' ')

                $renamedItems.Add($pageWithDuplicateName, $renamedName)
            }
            Else {
                $urlencodedPageName = formatPageName($pageWithDuplicateName)
                $urlencodedPageName = $urlencodedPageName.Replace('\', '%5C')
                $fileName = $localMachinePath + $urlencodedPageName + '.md'
                $newFilePath = getAlterNateFilePath $urlencodedPAgeName
                $newFileName = [System.IO.Path]::GetFileNameWithoutExtension($newFilePath)
                #$new = formatPageNameInLinks $newFileName
                $oldPageNameToNewHashTable[$newFileName] = $newFilePath
                $actualName = reverseFormatPageName $newFileName
                $renamedItems.Add($pageWithDuplicateName, $actualName)
            }
        }

       
        #$mediaWikiPageContainingSlash
        ForEach($item in $mediaWikiPageContainingSlash) {
            If($oldPageNameToNewHashTable.ContainsKey($mediaWikiPageContainingSlash)) {
                $oldname = $mediaWikiPageContainingSlash
                $newFilePath = $oldPageNameToNewHashTable[$mediaWikiPageContainingSlash]
                $newFileName = [System.IO.Path]::GetFileNameWithoutExtension($newFilePath).Replace('-', ' ')

                Write-Host $oldname ' : ' $newFileName
                $actualName = reverseFormatPageName $newFileName
                $renamedItems.Add($oldname, $actualName)

                
                #HandleREnamedPages $oldname $newName
            }
        }

        PreprocessRenamedArray

        HandleREnamedPages 
}

function PreprocessRenamedArray () {

    Write-Host '| BEFORE  PREPROCESSING | RENAMED ARR |'
    Write-Host '|-----------|------------------|'
    ForEach ($key in $renamedItems.Keys) {
        $val = $renamedItems[$key]
        Write-Host '|   ' $key '   |   ' $val '   |'
        
    }

    Write-Host '------------------------------------------------'
    ForEach ($key in @($renamedItems.Keys)) {
        $val = $renamedItems[$key]
        Write-Host $key ' :::: ' $val

        while($val -ne $null) {
            #Write-Host 'inside val with '$val
            
            If($renamedItems.ContainsKey($val)) {
                If($val -eq $renamedItems[$val]) {
                    $val = $null
                }
                Else {
                    $renamedItems[$key] = $renamedItems[$val]
                    $val = $renamedItems[$val]
                }
            }
            Else {
                $val = $null
            }
        }
    }

     Write-Host '| after PREPROCESSING | RENAMED ARR |'
     Write-Host '|--------------|---------------|'
    ForEach ($key in $renamedItems.Keys) {
        $val = $renamedItems[$key]
        Write-Host '|   ' $key '   |   ' $val '   |'
        #Write-Host '|-----------------------------|'
    }

    Write-Host '------------------------------------------------'
}

function handleRenamedPage($old, $new) {
    $mediaWikiGeBackLinksFullUrl = $mediaWikiCoreUrl + $mediaWikiGeBackLinksPartialUrl + $old
                $new = $new.TrimStart(':')
                $new = formatPageName $new
                Write-Host $mediaWikiGeBackLinksFullUrl ' :  mediaWikiGeBackLinksFullUrl'

                $res = Invoke-WebRequest -Uri $mediaWikiGeBackLinksFullUrl -WebSession (Get-WebSession) | ConvertFrom-Json

                $pagesToReplace = $res.query.backlinks

                if($pagesToReplace.Length -ne 0) {
                    Write-Host '##########################################################################'
                    ForEach($pageToReplace in $pagesToReplace) {
                            # find the current reference to the url
                            If($oldPageNameToNewHashTable.ContainsKey($pageToReplace.title)) {
                                Write-Host 'created file : ' $pageToReplace.title
                                $containingPageName = $oldPageNameToNewHashTable[$pageToReplace.title]
                                $fileToCreate = $containingPageName

                                Write-Host 'Replacing in file ' $fileToCreate
                                If(Test-Path $fileToCreate) {
                                    $newContent = Get-Content $fileToCreate -Raw
                                    $oldname = '(\(' + $old.Replace(' ', '-') + ' \))'
                                    $newName = '(' + $new.Replace(' ', '-') + ' )'

                                    Write-Host 'old str: '$oldname ' , newstr: ' $newName
                                   # Write-Host $newContent
                                    $newContent = $newContent -replace $oldname, $newName

                                    $oldname = '(\(' + $old.Replace(' ', '-') + '#(.*?) \))'
                                    $newName = '(' + $new.Replace(' ', '-') + ' #$2)'

                                    Write-Host 'old str: '$oldname ' , newstr: ' $newName
                                   # Write-Host $newContent
                                    $newContent = $newContent -replace $oldname, $newName
                                    Set-Content -Path $fileToCreate -Value $newContent
                                } Else {
                                    Write-Host $fileToCreate 'does not exists'
                                }
                            }
                            Else {
                                Write-Host 'not created file : ' $pageToReplace.title
                            }
                        }
                        Write-Host '##########################################################################'
                }
}

function HandleREnamedPages() {

    ForEach($key in $renamedItems.Keys) {
            $item = $renamedItems[$key]
            Write-Host '-------------------------------------------------------'
            Write-Host 'key: ' $key
            If($item -ne $null) {
            Write-Host 'item: ' $item
           # Write-Host 'File: ' $count
                $count++
                
                handleRenamedPage $key $item
            }
            Else {
                Write-Host 'Picked null item key' 
            }
        }
}
################################################################################

#################################git###########################################

function getGitUrlWithCreadentials() {
    $urlArr = $vstsWikiRemoteUrl -split 'https://'
    $url = 'https://' + $vstsUserName + '@' + $urlArr[1]
    Write-Host $url
    return $url
}

function initializeGit() {
    cd $rootPath
    $url = getGitUrlWithCreadentials
    git clone $url -v
    git pull
    cd $wikiName
    git checkout wikiMaster
}

function pushVSTSWiki() {
    git config core.autocrlf false
    #git remote add origin $vstsWikiRemoteUrl
    #git chekout 
    git add .
    git commit -m mediWiki
    #git remote add origin $vstsWikiRemoteUrl
    git push -f

}
###############################################################################

function migrateToVSTSWiki() {
    #create the page + category hierarcy (skip tempaltes)

    initializeGit

    #Write-Host 'Getting All Images'
    getAllImages 
    Write-Host 'Creating Hrchy'
    createPageHierarchy 
    
    Write-Host '--------------------Gettng content---------------------------'
    getPageContent 
    preProcessPages #both category and pages
    processPages
    postProcessPages

    handleSpecialPages

    pushVSTSWiki
}



migrateToVSTSWiki

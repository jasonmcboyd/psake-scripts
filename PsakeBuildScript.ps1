Framework "4.5.1"

Properties {
    # The path to the solution's root folder.
    $SolutionFolder = $SolutionFolder

    # The name of the .csproj file to be built and published.
    $ProjectFileName = $ProjectFileName

    # The folder where the build will be published.
    $PublishFolder = $PublishFolder

    # The project configuration to use when building the project.
    $Configuration = $Configuration

    # If true then the build artifacts folder will not be deleted.
    $DoNotCleanUpBuildArtifacts = $DoNotCleanUpBuildArtifacts

    # The prefix for the archive file's name, e.g. ClientPortalApi
    $ArchiveFileNamePrefix

    # Find the .csproj file to be built and published.
    $ProjectPath = (Get-ChildItem -Path "$SolutionFolder" -Recurse | Where-Object { $_.Name -eq "$ProjectFileName" } | Select-Object -First 1).FullName

    $TimeStamp = [System.DateTime]::Now.ToString("yyyyMMdd_HHmmss")

    # The path and file name that archive will be published to.
    $PublishPath = [System.Io.Path]::GetFullPath("$PublishFolder\$($ArchiveFileNamePrefix)_$($Configuration)_$($TimeStamp).zip")

    # Construct the build's archive file name.  This is what will ultimily get published to the publish folder.
    $BuildArchiveFileName = Split-Path $PublishPath -Leaf

    # Find the Visual Studio solution that contains the projects.
    $VisualStudioSolutionFile = (Get-ChildItem -Path "$SolutionFolder" -Recurse | Where-Object { $_.Extension -eq ".sln" } | Select-Object -First 1).FullName
    
    # Get the build artifacts directory name.  This is the directory where we will do work, i.e. copy files, rename files, build the archive, etc.
    $BuildArtifactsPath = Join-path "$PSScriptRoot" ("Build_$($Configuration)_$($TimeStamp)")

    # Get the project build artifacts directory name.
    $ProjectBuildArtifactsPath = Join-path "$BuildArtifactsPath" "Project"

    # Get the project build artifacts directory name.
    $WebBuildArtifactsPath  = Join-path "$BuildArtifactsPath" "Web"

    # Get the path to the final build archive file.
    $BuildArchiveFile = Join-Path "$BuildArtifactsPath" "$BuildArchiveFileName"
}

Task default -depends PublishBuild, CleanUp

Task ValidateParameters {
    # Assert that the solution path is not null, blank or white space.
    Assert `
        -conditionToCheck (![String]::IsNullOrWhiteSpace($SolutionFolder)) `
        -failureMessage "The 'SolutionFolder' property is required."

    # Assert that the project file name is not null, blank or white space.
    Assert `
        -conditionToCheck (![String]::IsNullOrWhiteSpace($ProjectFileName)) `
        -failureMessage "The 'ProjectFileName' property is required."

    # Assert that the project file name ends with .csproj.
    Assert `
        -conditionToCheck ($ProjectFileName.EndsWith('.csproj')) `
        -failureMessage "The project file name must end with .csproj."

    # Assert that the publish path is not null, blank or white space.
    Assert `
        -conditionToCheck (![String]::IsNullOrWhiteSpace($PublishPath)) `
        -failureMessage "The 'PublishPath' property is required."

    # Assert that project was found.
    Assert `
        -conditionToCheck (![String]::IsNullOrWhiteSpace($ProjectPath)) `
        -failureMessage "The project, '$ProjectFileName', could not be found in the solution folder or any of its subfolders."
}

Task RestoreNuget -depends ValidateParameters {
    Exec {
        nuget restore $VisualStudioSolutionFile
    }
}

Task DeleteBinAndObjFolders -depends ValidateParameters {
    Exec {
        Get-ChildItem -Path $SolutionFolder -Recurse -Directory | 
        Where-Object { $_.Name -match "^bin$|^obj$" } | 
        Remove-Item -Force -Recurse
    }
}

Task CleanProject -depends RestoreNuget, DeleteBinAndObjFolders {
    Exec {
        msbuild `
            "$VisualStudioSolutionFile" `
            /target:Clean `
            /property:Configuration="$Configuration" `
            /verbosity:quiet
    }
}

Task BuildProject -depends CleanProject {
    
    Exec {
        msbuild `
            "$ProjectPath" `
            /target:Rebuild `
            /property:Configuration="$Configuration" `
            /property:OutDir="$ProjectBuildArtifactsPath" `
            /property:UseWPP_CopyWebApplication=True `
            /property:PipelineDependsOnBuild=False `
            /property:WebProjectOutputDir="$WebBuildArtifactsPath" `
            /property:WarningLevel=0 `
            /verbosity:quiet
    }
}

Task RenameWebConfig -depends BuildProject {
    # Append '.example' to the end of the web.config file.
    # This is to prevent the web.config file on the deployment server from being replaced on accident.
    $webConfigFile = Get-Item -Path (Join-Path $WebBuildArtifactsPath "web.config")
    if ($webConfigFile -ne $null) {
        Rename-Item -Path $webConfigFile.FullName -NewName ($webConfigFile.Name + ".example")
    }
}

Task ArchiveBuild -depends RenameWebConfig {

    $artifactsPath = $WebBuildArtifactsPath

    $filesToZip = Get-ChildItem $artifactsPath -Recurse

    Compress-Archive `
        -Path $artifactsPath `
        -DestinationPath $BuildArchiveFile `
        -CompressionLevel Fastest
}

Task PublishBuild -depends ArchiveBuild {
    Copy-Item -Path $BuildArchiveFile -Destination $PublishPath -Force
}

Task CleanUp -depends PublishBuild -precondition { !$DoNotCleanUpBuildArtifacts } {
    Remove-Item $BuildArtifactsPath -Recurse 
}

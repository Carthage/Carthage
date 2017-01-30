# Version Files

This document describes the purpose and format of version files.

#### File location and format

In order to avoid rebuilding frameworks unnecessarily, Carthage stores cache data in invisible version files in the Build folder.  Version files are named ".Project.version" (where Project is the name of a project).

Each version file contains JSON data in a format similar to that of the version file for .Prelude.version:

    {
      "commitish" : "1.6.0",
      "Mac" : [
       {
           "sha1" : "ad4c4bfe83c546d18418825b8c481df11b3910cc",
           "name" : "Prelude"
       }
      ]
    }

#### Caching builds with version files

When a project is built, an entry is added to or updated in the version file for each platform with a built scheme, even if no frameworks are produced (in which case the "cachedFrameworks" key is associated with an empty array).  For each platform, the dependency’s comitish and the SHA1 for each produced framework are recorded.

Before a project is built, if a version file already exists, it will be used to determine whether Carthage can skip building the project.  For a given platform, if the comitish matches and the recorded SHA1 of each associated framework matches the SHA1 of those frameworks in the Build folder, that platform is considered cached.  If no platforms are provided as build options (via --platform), a dependency will be considered cached if the platforms listed in the version file are considered cached (in order to prevent a dependency from always being rebuilt if it does not have a buildable scheme for all platforms).  If platforms are provided as build options, a dependency will be considered cached only if the version file contains an entry for every provided platform and each of those platforms are considered cached.

Version files will be ignored and all dependencies will be built if --no-cache-build is provided as a build option.  Version files may also be manually deleted in order to clear Carthage’s cache data.  Version files are always produced after a project has been built.

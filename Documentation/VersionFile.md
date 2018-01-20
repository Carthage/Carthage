# Version Files

This document describes the purpose and format of version files.

#### File location and format

In order to avoid rebuilding frameworks unnecessarily, Carthage stores cache data in hidden version files in the Build folder.  Version files are named ".Project.version" (where Project is the name of a project).

Each version file contains JSON data in a format similar to that of the version file for .Prelude.version:

    {
      "commitish" : "1.6.0",
      "Mac" : [
       {
           "hash" : "de07bfdba346deb20705712c2ea07e7191d57f07d793c8c0698ded085bdb5cce",
           "name" : "Prelude"
       }
      ]
    }

#### Caching builds with version files

When a project is built, a version file is created with the dependency's commitish. An entry is added in the version file for each platform that was built, even if no frameworks are produced (in which case the given platform key is associated with an empty array).  For each platform, the name and hash (SHA256) for each produced framework are recorded.

Before a project is built, if a version file already exists, it will be used to determine whether Carthage can skip building the project.  For a given platform, if the commitish matches and the recorded hash of each associated framework matches the hash of those frameworks in the Build folder, that platform is considered cached.  If no platforms are provided as build options (via `--platform`), a dependency will be considered cached if all platforms are listed in the version file and considered cached. If platforms are provided as build options, a dependency will be considered cached if the version file contains an entry for every provided platform and each of those platforms are considered cached.

Version files will be ignored and all dependencies will be built unless `--cache-builds` is provided as a build option.  Version files may also be manually deleted in order to clear Carthage’s cache data.  Version files are always produced after a project has been built.

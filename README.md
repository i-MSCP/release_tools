# Release Tools

Repository containing tools for i-MSCP

## release.sh

This script allows to release new i-MSCP version for the specified branch. In order, it will:

- clone remote GitHub repository if needed
- update CHANGELOG, INSTALL, release and imscp.conf files
- pull last portable object files from Transifex and compile machine object files
- Build new portable object template file and send it to Transifex
- pull up-to-date portable object files from Transifex )
- commit changes on GitHub and add git tag for new i-MSCP version
- update git repository for development
- pack new version archives and send them to SourceForge

**Usage example:**

```shell
$ sh ./release.sh -b 1.2.x -r 1.2.3 -t '<transifex_username>:<transifex_password>' -m 'Laurent Declercq' -f nuxwin -s -d
```

**Note:** You must have write access on both GitHub repository and SourceForge.

## translation.sh

This script allows to update i-MSCP core translation files for the specified i-MSCP branch. In order it will:

- Clone remote GitHub repository if needed
- pull last portable object files from Transifex and compile machine object files
- Build new portable object template file and send it to Transifex
- pull up-to-date portable object files from Transifex 
- commit changes on GitHub 

**Usage example:** 

```
$ sh ./translation.sh -b 1.2.x -t '<transifex_username>:<transifex_password>' -s
```

**Note:** You must have write access on GitHub repository.

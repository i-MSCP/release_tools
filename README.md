# i-MSCP utility scripts

Provides some utility scripts for i-MSCP.

## release.sh script

This script allows to release a new i-MSCP version for the specified branch. In order, it will:

- Clone remote GitHub repository if needed
- Update CHANGELOG, INSTALL, release and imscp.conf files
- Commit changes on GitHub and add git tag for new i-MSCP version
- Update git repository for development
- Pack new version archives and send them to SourceForge

### Usage example

```sh
$ sh ./release.sh -b 1.2.x -r 1.2.3 -m 'Laurent Declercq' -f nuxwin -s -d
```

**Note:** You must have write access on GitHub repository and SourceForge.

## translation.sh script

This script allows to update i-MSCP core translation files for the specified i-MSCP branch. In order it will:

- Clone remote GitHub repository if needed
- Update resource translation file on Transifex (pot file)
- Pull latest po files from Transifex
- Build machine object files 
- Commit changes on GitHub 

### Usage example

```sh
$ sh ./translation.sh -b 1.2.x -t '<transifex_username>:<transifex_password>' -s
```

**Note:** You must have write access on GitHub repository.

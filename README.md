# devenv
Basic must-haves for a convenient general infrastructure setup of C++ apps/libs, to be used as a
git submodule.

## Installation

Add it as a git submodule to your project repo, i.e. from the repo dir run
```bash
git submodule add git@github.com:devmarkusb/devenv.git
```
Then
```bash
python3 -m venv venv
. venv/bin/activate
pip install pre-commit
pre-commit install
# and optionally right away
pre-commit run --all-files
```

## Usage of the submodule 
Later, after updating or cloning (or whatever) your main repo you sometimes need to
```bash
git submodule update --init --recursive --recommend-shallow
```
from your main repo dir, or just use the convenience script
```bash
devenv/git-sub.sh
```

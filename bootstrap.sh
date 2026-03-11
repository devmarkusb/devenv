#!/usr/bin/env bash

python3 -m venv .venv
source .venv/bin/activate
pip install pre-commit
pre-commit install

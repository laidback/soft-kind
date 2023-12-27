# Soft-Kind Repository

## Introduction

Welcome to the `soft-Kind` repository. This repository contains a script file written in Bash language that is used to set up a Kubernetes in Docker (kind) software development environment.

In this setup, the tool performs the following operations:
- Installation of required tools (kind and flux)
- Creation of a kind cluster if not already present
- Installation of flux if not already present
- Flux bootstrapping with Github or Gitlab

## Prerequisites
Please make sure that you have the following installed:
- Bash: The script is written in Bash. Make sure you have it installed.
- GoLanguage: The script uses Go to install kind if it is not found. If you need to install Go, you can follow instructions [here](https://golang.org/doc/install).

## Setup
The setup script consists of various functions, each performing a certain task. Below are the descriptions of the processes that happen in setting up the tools and the environment:

- The `create_cluster` function checks if a kind cluster named "kind" exists. If it exists, the user is prompted to confirm if they want to destroy the existing "kind" cluster. If it doesn't exist, it's created.

- The `bootstrap_flux` function checks if Flux is installed and, if not found, installs it. If installed, the user is asked to confirm destroying the installation before a new installation is made.

- The `bootstrap_github` function bootstraps Flux with Github.

- The `bootstrap_gitlab` function bootstraps Flux with Gitlab.



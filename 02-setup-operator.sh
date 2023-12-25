#!/usr/bin/env bash

set -o nounset

# variables
host="$(ls -1 $REPOS | gum choose)"
test -z $host && exit 1
group="$(ls -1 $REPOS/$host | gum choose)"
test -z $group && exit 1
project="$(ls -1 $REPOS/$host/$group | gum choose)"
test -z $project && exit 1
repo="${GITLAB_REPO:-$host/$group/$project}"

# variables
domain="laidback.github.io"
project="softer"
owner="laidback"
repo="github.com/laidback/softer"
version="v1alpha1"
err=0

# init operator-sdk project in go
init_go_operator() {

    # get user inputs
    local dir=$(gum input --prompt "Dir: " --value "go-operator")
    [ -z $dir ] && return $err
    local domain=$(gum input --prompt "Domain name: " --value "$domain")
    [ -z $domain ] && return $err
    local project=$(gum input --prompt "Project name: " --value "$project")
    [ -z $project ] && return $err
    local owner=$(gum input --prompt "Owner: " --value "$owner")
    [ -z $owner ] && return $err
    local repo=$(gum input --prompt "Repo: " --value "$repo")
    [ -z $repo ] && return $err
    local version=$(gum input --prompt "Version: " --value "$version")
    [ -z $version ] && return $err

    # if exists, cd into it
    if [ -d "$dir" ]; then
        gum confirm "delete $dir?" && rm -rf "$dir"
    fi
    mkdir -p "$dir" && cd "$dir" || exit

    go mod init $domain/$project
    operator-sdk init \
        --domain $domain \
        --project-name $project \
        --owner $owner \
        --repo $repo \
        --plugins "go/v4"
    go mod tidy && go mod vendor
}

# init operator-sdk project with helm chart
# in a separate directory. This is a workaround
# for the issue with the operator-sdk helm plugin
# and go plugin in the same project.
init_helm_operator() {

    # get user inputs
    local dir=$(gum input --prompt "Dir: " --value "helm-operator")
    [ -z $dir ] && return $err
    local domain=$(gum input --prompt "Domain name: " --value "$domain")
    [ -z $domain ] && return $err
    local project=$(gum input --prompt "Project name: " --value "$project")
    [ -z $project ] && return $err
    local kind=$(gum input --prompt "Kind: " --value "Softserve")
    [ -z $kind ] && return $err
    local version=$(gum input --prompt "Version: " --value "v1alpha1")
    [ -z $version ] && return $err

    # if exists, cd into it
    if [ -d "$dir" ]; then
        gum confirm "delete $dir?" && rm -rf "$dir"
    fi
    mkdir -p "$dir" && cd "$dir" || exit

    operator-sdk init \
        --domain $domain \
        --project-name $project \
        --kind $kind \
        --version $version \
        --plugins "helm/v1"
}

# merge helm chart into the operator-sdk go project
merge_operators() {
    local merge_operators=( "go-operator" "helm-operator" )

    local project=$(gum input --prompt "Project name: " --value "$project")
    [ -z $project ] && return $err

    # select go operator to merge
    local go_operator=$(echo "go-operator" | xargs gum choose --select-if-one)
    [ -z $go_operator ] && return $err

    # select helm operator to merge
    local helm_operator=$(echo "helm-operator" | xargs gum choose --select-if-one)
    [ -z $helm_operator ] && return $err

    # check if $project exists and ask to delete
    if [ -d "$project" ]; then
        gum confirm "delete $project?" && rm -rf "$project"
    fi

    # init $project dir and cd into it
    mkdir -p "$project" && cd "$project" || exit

    # GO OPERATOR
    # copy files from go-operator into $project dir
    cp -r ../go-operator/* .

    # mv files to avoid conflict with helm chart
    mv ./Dockerfile ./go-operator.Dockerfile
    mv ./Makefile ./go-operator.Makefile

    # HELM OPERATOR
    # copy files from helm-operator into $project dir
    cp -r ../helm-operator/helm-charts .
    cp -r ../helm-operator/config/crd .
    cp -r ../helm-operator/config/samples .

    # mv files to avoid conflict with go-operator
    cp ../helm-operator//Dockerfile ./helm-chart.Dockerfile
    cp ../helm-operator/Makefile ./helm-chart.Makefile

    # watches.yaml is not a problem, we need only the go one
    cp ../helm-operator/watches.yaml ./watches.yaml

    # merge helm chart into the operator-sdk go project
    # config dir seems to be no problem, copy files and prefix with helm
#    for file in $(ls ../helm-operator/config); do
#        cp -r "config/$file" "../config/helm-chart-$file"
#    done

    # cleanup helm project and cd back to the operator-sdk go project
    gum confirm "delete operands?" && rm -rf go-operator helm-operator
}

# array of functions in this script
declare -a functions=(
    "init_go_operator"
    "init_helm_operator"
    "merge_operators"
)

# main function
main() {
    local err=0

    # select command to run
    local selected=$(echo "${functions[@]}" | \
        xargs gum choose --no-limit --ordered --select-if-one)

    for cmd in $selected; do
        $cmd
    done
}

# run main function portable for bash and zsh shells
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "main function"
    main "$@"
fi


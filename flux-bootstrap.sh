#!/usr/bin/env bash

set -o nounset
set -o errexit
set -o pipefail

# variables
SCRIPT_DIR=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

# define env var logger, provide default value
print_env() {
    cat << EOF
    # GitLab
    #
    # host: ${host:-}
    # group: ${group:-}
    # repo: ${repo:-}
    # repo_path: ${repo_path:-}
    # local_repo: ${local_repo:-}
    # local_repo_file: ${local_repo_file:-}
    # branch: ${branch:-main}
    # namespace: ${namespace:-}
    # remote_registry: ${remote_registry:-}
    # tag: ${tag:-}
EOF
}

# registries array
declare -a registries=(
    "ghcr.io"
    "quay.io"
    "docker.io"
)

# navigate to the flux-gitops repository
navigate(){
    local err=0
    local ret=""

    # set fix flux-gitops repository path
    gitops_namespace="ghcr-flux-system"
    host="$(ls $REPOS | gum choose)"
    group="$(ls $REPOS/$host | gum choose)"
    repo="$(ls $REPOS/$host/$group | gum choose)"
    repo_path="clusters/kind"

    # get kubernetes namespace where to create the secret or create new
    mode=$(echo -e "existing\nnew" | gum choose --header "Choose namespace mode")
    if [[ "$mode" == "new" ]]; then
        namespace="$(gum input --prompt 'provide the namespace name: ')"
        kubectl create namespace "$namespace"
        mkdir -p "$local_repo/$namespace"
    else
        # get kubernetes namespace where to create the secret
        namespace="$(kubectl get namespaces | cut -d' ' -f1 | gum choose)"
    fi

    # setup local repo path to the secret file, create dir if not exists
    local_repo_path="$REPOS/$host/$group/$repo/$repo_path/$namespace"
    mkdir -p "$local_repo_path" || echo "could not create $local_repo_path" 1>&2
}

# create regcred for specific host, group and repo
# get the input from user using gum choose
create_regcred(){

    # navigate to the flux-gitops repository
    navigate
    local_repo_file="$local_repo_path/$namespace-regcred.yaml"

    # get remote registry
    remote_registry="$(echo "${registries[@]}" | xargs gum choose)"
    print_env

    # create regcred for specific host, group and repo
    echo -e "create kube secret for $namespace"
    flux create secret oci "${namespace}-regcred" \
        --url="$remote_registry" \
        --username="${namespace}-regcred" \
        --password="$(gum input --prompt 'provide the regcred password: ')" \
        --namespace="${gitops_namespace}" \
        --export > "$local_repo_file"
        #--export | kubectl apply -f -
}

# create flux helm source
create_source(){

    # navigate to the flux-gitops repository
    navigate
    local_repo_file="$local_repo_path/$namespace-source.yaml"
    print_env

    # create flux helm source
    echo -e "create flux source for $namespace"
    flux create source helm "${namespace}-helm-repository" \
        --url "oci://${host}/${group}/${namespace}" \
        --namespace "${gitops_namespace}" \
        --interval 1m \
        --secret-ref "${namespace}-regcred" \
        --export > "$local_repo_file"
}

# create flux release / helm release
create_release(){

    # navigate to the flux-gitops repository
    navigate
    local_repo_file="$local_repo_path/$namespace-release.yaml"
    print_env

    # create flux helm release
    # we navigated to the flux-gitops repository, which means, we have
    # some variables defined, like host, group, repo, repo_path, local_repo
    echo -e "create flux helm release for $namespace"
    flux create helmrelease "${namespace}-helm-release" \
        --chart "${namespace}" \
        --chart-version "*" \
        --crds "CreateReplace"\
        --target-namespace "${namespace}" \
        --create-target-namespace true \
        --source "HelmRepository/${namespace}-helm-repository" \
        --namespace "${gitops_namespace}" \
        --interval 1m \
        --export > "$local_repo_file"
}

# create flux kustomization
create_kustomization(){

    # navigate to the flux-gitops repository
    navigate
    local_repo_file="$local_repo_path/$namespace-kustomization.yaml"
    print_env

    # create flux kustomization
    echo -e "create flux helm kustomization for $namespace"
    flux create kustomization "${namespace}-flux-kustomization" \
        --target-namespace="${namespace}" \
        --source="${namespace}-helm-repository" \
        --namespace="${gitops_namespace}" \
        --path="./kustomize" \
        --prune=true \
        --wait=true \
        --interval=1m \
        --retry-interval=2m \
        --health-check-timeout=3m \
        --export > "$local_repo_file"
}

main() {
    cmds=(
        "create_regcred"
        "create_source"
        "create_release"
        "create_kustomization"
    )

    selected=$(gum choose --header "Choose command to run" --no-limit "${cmds[@]}")

    # run all selected commands
    for cmd in "${selected[@]}"; do
        echo "INFO: running $cmd"
        $cmd
    done
}

# bash guard to call main function only if executed as script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi


#!/usr/bin/env bash

set -o nounset
set -o errexit
set -o pipefail

# check if required tools are installed
command -v kind >/dev/null || {
    echo "kind not found installing ..."
    go install sigs.k8s.io/kind@v0.20.0
}

# check if required tools are installed
command -v flux >/dev/null || {
    echo "flux not found installing ..."
    curl -sL https://toolkit.fluxcd.io/install.sh | sudo bash
}

# setup kind cluster if not exists
create_cluster(){
    local err=0
    local ret=""
    local cluster="kind"
    local config="kind/kind-config.yaml"

    # check if kind cluster exists
    ret=$(kind get clusters 2>&1 | grep -e "^$cluster"); err=$?

    # check if kind cluster exists
    # confirm if it should be destroyed with gum confirm
    if [[ "$err" -eq 0 ]]; then
        gum confirm "destroy kind cluster $cluster?" \
            && kind delete cluster --name "$cluster" \
            || return 1
    fi

    echo "kind cluster $cluster not found creating ..." 1>&2
    ret=$(kind create cluster --name "$cluster" \
        --config "$config"); err=$?

    if [[ "$err" -ne 0 ]]; then
        echo "could not setup kind ..." 1>&2
        echo -e "ret: $ret\nerr: $err" 1>&2
        return $err
    fi
    export KUBECONFIG="$HOME/.kube/$cluster"
}

# install flux if not installed and precheck
bootstrap_flux(){
    local err=0
    local flux_version="latest"
    local flux_namespace="flux-system"
    local flux_components="image-reflector-controller,image-automation-controller"

    echo "checking if flux is installed ..."
    # check if flux is installed
    ret=$(flux check --pre --kubeconfig "$KUBECONFIG")

    # check if flux is installed
    # confirm if it should be destroyed with gum confirm
    if [[ "$err" -eq 0 ]]; then
        gum confirm "destroy flux?" \
            && flux uninstall --kubeconfig "$KUBECONFIG" \
            || return 1
    fi

    echo "flux not installed installing ..."
    ret=$(flux install --version=${flux_version} \
        --components-extra=${flux_components} \
        --namespace=${flux_namespace} \
        --network-policy=false \
        --kubeconfig "$KUBECONFIG"); err=$?

    if [[ "$err" -ne 0 ]]; then
        echo "could not install flux ..."
        echo -e "ret: $ret\nerr: $err"
        return $err
    fi
}

# flux bootstrap with github if not bootstrapped
bootstrap_github() {
    local err=0
    local ret=""

    # definte git config variables
    local host="${host:-$(ls -1 $REPOS | gum choose)}"; err=$?
    test $err -ne 0 && exit $err

    local group="${group:-$(ls -1 $REPOS/$gitlab_host | gum choose)}"; err=$?
    test $err -ne 0 && exit $err

    local repo="softer"
    local path="clusters/kind"
    local branch="main"

    local flux_namespace="ghcr-flux-system"

    ret=$(flux bootstrap github \                                                                                                                                                                                          (󱃾|kind-kind@kind-kind/) |  | laid@disco
      --hostname "${host}" \
      --repository "${repo}" \
      --owner "${group}" \
      --personal \
      --path "${path}" \
      --branch ${branch} \
      --insecure-skip-tls-verify \
      --kubeconfig "${KUBECONFIG}" \
      --namespace "ghcr-flux-system" \
      --token-auth); err=$?

    echo "bootstrapping github ..."
    if [[ "$err" -ne 0 ]]; then
        echo "could not bootstrap github ..."
        echo -e "ret: $ret\nerr: $err"
        return $err
    fi
}

# flux bootstrap with gitlab if not bootstrapped
bootstrap_gitlab() {
    local err=0
    local ret=""

    # definte gitlab config variables - bootstrap gitlab
    local gitlab_host="${host:-$(ls -1 $REPOS | gum choose)}"; err=$?
    test $err -ne 0 && exit $err

    local gitlab_group="${group:-$(ls -1 $REPOS/$gitlab_host | gum choose)}"; err=$?
    test $err -ne 0 && exit $err

    local gitlab_repo="flux-gitops"
    local gitlab_path="clusters/kind"
    local gitlab_branch="main"

    local flux_namespace="flux-system"

    ret=$(flux bootstrap gitlab \
        --hostname "${gitlab_host}" \
        --owner "${gitlab_group}" --personal \
        --repository "${gitlab_repo}" \
        --path "${gitlab_path}" \
        --branch "${gitlab_branch}" \
        --deploy-token-auth \
        --insecure-skip-tls-verify true \
        --kubeconfig "${KUBECONFIG}" \
        --namespace "${flux_namespace}"); err=$?

    echo "bootstrapping gitlab ..."
    if [[ "$err" -ne 0 ]]; then
        echo "could not bootstrap gitlab ..."
        echo -e "ret: $ret\nerr: $err"
        return $err
    fi
}

# array of functions in this script
declare -a functions=(
    "print_env"
    "create_cluster"
    "bootstrap_flux"
    "bootstrap_github"
    "bootstrap_gitlab"
)

# main function calling all other functions
main(){
    local err=0

    # get user inputs via gum choose on which function to run
    local func=$(echo "${functions[@]}" | xargs gum choose)
    echo "running $func ..."
    [ -z $func ] && return 1

    # call function by name
    $func

    cat << EOF
    # clone GitOps repository
    git clone flux-gitops repository gitops_repo
    cd gitops_repo

    # bootstrap GitOps repository
    # deploys flux components to cluster
    ./bootstrap.sh
EOF
}

# bash guard to call main function only if executed as script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi


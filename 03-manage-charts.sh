#!/usr/bin/env bash

# In this script we use the following conventions:
# * speak in terms of GitLab CI/CD mostly and stay compatible
# e.g. we use our own internal variables in lower case,
# but we use GitLab CI/CD variables in upper case (e.g. CI_REGISTRY_IMAGE)
# to override the default behavior of the script, you can set the following
# environment variables:
#    RELEASE_VERSION: ${RELEASE_VERSION}
#    registry: ${registry} - ${CI_REGISTRY_IMAGE}
#    registry_user: ${registry_user} - ${CI_JOB_USER}
#    registry_password: ${registry_password} - ${CI_JOB_TOKEN}
#    charts_path: ${charts_path}
#    chart_name: ${chart_name} - ${CI_PROJECT_NAME}
#    cmds: ${cmds}

set -o nounset
#set -o errexit
set -o pipefail

# set script variables
RELEASE_VERSION="0.0.0"
registry="${CI_REGISTRY_IMAGE:-registry.asmgmt.hilti.com}"
registry_user="${CI_JOB_USER:-lukas.ciszewski}"
registry_password="${CI_JOB_TOKEN:-}"
charts_repo="soft-serve"
charts_path="charts"
chart_name="${CI_PROJECT_NAME:-soft-serve}"

# helm registry login ${registry} \
#  --username ${registry_user} \
#  --password ${registry_password}
#
# helm push ${chart_name}-${RELEASE_VERSION} \
#  ${registry}/${registry_user}/${charts_path}
#
# helm pull oci://registry.asmgmt.hilti.com/lukas.ciszewski/soft-serve/soft-serve --version 1.10.1

# push helm chart to registry
push_chart(){
    local err=0
    local ret=""

    export $(cat release.env)
    echo "INFO: pushing chart ${chart_name}"
    echo "INFO: version is ${RELEASE_VERSION}"
    echo "INFO: registry path is ${registry}/${registry_user}/${charts_repo}"
    echo "INFO: registry chart is ${chart_name}-${RELEASE_VERSION}.tgz"

    helm registry login "${registry}" \
        --username "$registry_user" \
        --password "$registry_password"

    # push helm chart to registry
    helm push "${chart_name}-${RELEASE_VERSION}.tgz" \
        oci://${registry}/${registry_user}/${charts_repo}
}

# package helm chart and push to registry
package_chart(){
    local err=0
    local ret=""

    export $(cat release.env)
    echo "INFO: packaging chart ${chart_name}" 2>&1
    echo "INFO: packaging version ${RELEASE_VERSION}" 2>&1
    # package helm chart and update the version and app-version in Chart.yaml
    # this bumps the version of the chart, which comes from the
    # semantic-release in the pipeline, e.g. 1.2.3 -> 1.2.4

    yq eval ".version = \"${RELEASE_VERSION}\"" \
       --inplace "${charts_path}/${chart_name}/Chart.yaml"

    yq eval ".appVersion = \"${RELEASE_VERSION}\"" \
       --inplace "${charts_path}/${chart_name}/Chart.yaml"

    helm package "${charts_path}/${chart_name}" --destination .
}

# commit the changes to the git repository
commit_changes(){
    local err=0
    local ret=""
    local image="${registry}/${registry_user}/${1:-soft-serve}"

    npx --yes \
        --package @semantic-release/changelog \
        --package @semantic-release/git \
        --package @semantic-release/exec \
        --package @semantic-release/commit-analyzer \
        --package conventional-changelog-conventionalcommits \
        semantic-release --no-ci \
        --plugins @semantic-release/commit-analyzer\
            @semantic-release/release-notes-generator \
            @semantic-release/changelog \
            @semantic-release/exec \
            @semantic-release/git \
        --repository-url file://$(pwd)

    # get the version from semantic-release
    test -z "${RELEASE_VERSION}" && {
        echo "ERROR: version is required"
        return 1
    };

    # updated release.env with the new version
    export $(cat release.env)
    echo "RELEASE_VERSION=${RELEASE_VERSION}"

    yq eval ".version = \"${RELEASE_VERSION}\"" \
       --inplace "${charts_path}/${chart_name}/Chart.yaml"

    yq eval ".appVersion = \"${RELEASE_VERSION}\"" \
       --inplace "${charts_path}/${chart_name}/Chart.yaml"

    # git add and commit the changes
    git add "${charts_path}/${chart_name}/Chart.yaml"
    git add "changelog.md"
    git add "release.env"
    git commit -m "chore(release): ${chart_name}-${image}-${RELEASE_VERSION}"

    # push the changes to the remote repository
    git push origin HEAD:main
    git push --tags

    return ${err}
}

# update helm chart fields in values.yaml
# image registry and image tag
update_chart(){
    local err=0
    local ret=""
    local image="${registry}/${registry_user}/${1:-soft-serve}"
    local version="${2:-0.0.0}"

    # update chart image version in values.yaml
    # this bumps the version of the package, e.g
    # nginx:1.2.3 -> nginx:1.2.4
    # TODO: get the image repository of the respective project the chart belongs to
    image=$(gum input \
        --placeholder "Enter the chart image:" \
        --value "${image}")

    # dynamically, so the mgmt maintenance team can use this script
    version=$(gum input \
        --placeholder "Enter the chart version:")

    yq eval ".image.repository = \"${image}\"" \
       --inplace "${charts_path}/${chart_name}/values.yaml"

    yq eval ".image.tag = \"${version}\"" \
       --inplace "${charts_path}/${chart_name}/values.yaml"

    # git add and commit the changes
    git add "${charts_path}/${chart_name}/values.yaml"
    git commit -m "fix: ${chart_name}-${image}-${version}"
}

# delete a helm chart from the local repository
# chart_name: name of the chart to delete via gum choose
delete_chart(){
    local err=0
    local ret=""

    echo "INFO: deleting chart ${chart_name}"
    # test if chart_name is given and not empty using test
    test -z "${chart_name}" && {
        echo "ERROR: chart name is required"
        return 1
    }

    # test if chart name is given and not empty using test
    test -d "${charts_path}/${chart_name}" && {
        # confirm deletion via gum confirm
        ret=$(gum confirm "Delete chart ${chart_name}?"); err=$?
        ret=$(rm -rf "${charts_path}/${chart_name}"); err=$?

        # check the return value of rm using test
        echo "INFO: chart deleted"
        return ${err}
    }
}

# create a new helm chart using helm create
create_chart(){
    local err=0
    local ret=""

    # test if chart_name is given and not empty using test
    test -z "${chart_name}" && {
        echo "ERROR: chart name is required"
        return 1
    }

    # test if chart already exists using test
    test -d "${charts_path}/${chart_name}" && {
        echo "ERROR: chart already exists"
        return 1
    }

    # create the chart
    ret=$(helm create "${charts_path}/${chart_name}"); err=$?

    # check the return value of helm create using test
    # shellcheck disable=SC2181
    test "${err}" -ne 0 && {
        echo "ERROR: failed to create chart"
        return ${err}
    }

    echo "INFO: chart created"
    return ${err}
}

# get the version from the git tag
get_env(){
    # print script variables using cat and heredoc
    cat <<EOF
    release_version: ${RELEASE_VERSION}
    registry: ${registry} - ${CI_REGISTRY_IMAGE:-}
    registry_user: ${registry_user} - ${CI_JOB_USER:-}
    registry_password: ${registry_password} - ${CI_JOB_TOKEN:-}
    charts_path: ${charts_path}
    chart_name: ${chart_name} - ${CI_PROJECT_NAME:-}
EOF
}

# main function calling all other functions
main(){
    local debug="${DEBUG:-false}"
    local err=0
    local ret=""

    # get the command line arguments using gum choose
    # shellcheck disable=SC2206
    cmds=( \
        create_chart \
        update_chart \
        commit_changes \
        package_chart \
        push_chart \
        delete_chart \
        get_env \
    )
    cmd=$(echo "${cmds[@]}" | xargs gum choose)

    # show the environment variables if debug is enabled
    # shellcheck disable=SC2154
    [[ "${debug}" == "true" ]] && get_env
    get_env

    # check if we have a read or write command and get the
    # chart name from the command line arguments
    if [[ "${cmd}" == "create_chart" ]]; then
        chart_name=$(gum input --placeholder "Enter the name of the chart:")
    else
        chart_name=$(ls "${charts_path}/" | gum choose)
    fi

    # invoke the command provided by the user
    # we provide all arguments to the command via env variables
    ${cmd}
    echo "INFO: command ${cmd} finished"
}

# bash guard to call main function only if executed as script
# configured to work also with zsh (see https://stackoverflow.com/a/28776166)
if [[ "${BASH_SOURCE[0]}" == "${0}" || "${ZSH_EVAL_CONTEXT}" == "toplevel" ]]; then
    main
fi


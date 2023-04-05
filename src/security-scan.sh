#!/bin/bash

set -euo pipefail

function github_folder_checks() {
    echo "Checking for files in the .github folder"
    if [ ! -d "action/.github" ] ; then
        echo "has_github_folder=false" >> $GITHUB_OUTPUT
        echo "has_workflows_folder=false" >> $GITHUB_OUTPUT
        echo "has_dependabot_configuration=false" >> $GITHUB_OUTPUT
        echo "has_codeql_init=false" >> $GITHUB_OUTPUT
        echo "has_codeql_analyze=false" >> $GITHUB_OUTPUT

        exit 0
    fi

    echo "has_github_folder=true" >> $GITHUB_OUTPUT

    if [[ -n $(find action/.github -maxdepth 1 -name dependabot.yml) ]] ; then
        echo "has_dependabot_configuration=true" >> $GITHUB_OUTPUT
    else
        echo "has_dependabot_configuration=false" >> $GITHUB_OUTPUT
    fi

    if [ ! -d "action/.github/workflows" ]; then
        echo "has_workflows_folder=false" >> $GITHUB_OUTPUT
        echo "has_codeql_init=false" >> $GITHUB_OUTPUT
        echo "has_codeql_analyze=false" >> $GITHUB_OUTPUT

        exit 0
    fi

    echo "has_workflows_folder=true" >> $GITHUB_OUTPUT

    # Look for CodeQL init workflow
    if [ `grep action/.github/workflows/*.yml -e 'uses: github/codeql-action/init' | wc -l` -gt 0 ]; then
        WORKFLOW_INIT=`grep action/.github/workflows/*.yml -e 'uses: github/codeql-action/init' -H | cut -f1 -d' ' | sed "s/:$//g"`
        echo "workflow_with_codeql_init=${WORKFLOW_INIT}" >> $GITHUB_OUTPUT
        echo "has_codeql_init=true" >> $GITHUB_OUTPUT
    else
        echo "has_codeql_init=false" >> $GITHUB_OUTPUT
    fi

    # Look for CodeQL analyze workflow
    if [ `grep action/.github/workflows/*.yml -e 'uses: github/codeql-action/analyze' | wc -l` -gt 0 ]; then
        WORKFLOW_ANALYZE=`grep action/.github/workflows/*.yml -e 'uses: github/codeql-action/analyze' -H | cut -f1 -d' ' | sed "s/:$//g"`
        echo "workflow_with_codeql_analyze=${WORKFLOW_ANALYZE}" >> $GITHUB_OUTPUT
        echo "has_codeql_analyze=true" >> $GITHUB_OUTPUT
    else
        echo "has_codeql_analyze=false" >> $GITHUB_OUTPUT
    fi
}

function action_docker_checks() {
    echo "Checking for docker configuration"
    if [ "docker" != `yq e '.runs.using' action/action.yml` ] ; then
        echo "action_uses_docker=false" >> $GITHUB_OUTPUT
        exit 0
    fi

    echo "action_uses_docker=true" >> $GITHUB_OUTPUT

    echo "Installing trivy"
    sudo apt-get install wget apt-transport-https gnupg lsb-release
    wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
    echo deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main | sudo tee -a /etc/apt/sources.list.d/trivy.list
    sudo apt-get update
    sudo apt-get install trivy

    if [ "Dockerfile" == `yq e '.runs.image' action/action.yml` ]; then
        echo "Scan docker image with trivy"
        docker build -t action-checkout/$ACTION action/
        trivy --quiet image action-checkout/$ACTION > issues
        docker image rm action-checkout/$ACTION
        else
        IMAGE=`yq e '.runs.image' action/action.yml`
        if  [[ $IMAGE = docker://* ]] ; then
            IMAGE=${IMAGE#docker://}
        fi
        echo "Scan docker image with trivy [$IMAGE]"
        trivy --quiet image $IMAGE > issues
    fi

    echo "Trivy results file        --------------------------------------------------------------------------------------------------------"
    cat issues
    echo "End of Trivy results file --------------------------------------------------------------------------------------------------------"

    echo "Checking for trivy issues count:"
    # Check if LOW or MEDIUM issues are found (remove count from header)
    LOW_MEDIUM_ISSUES=$(cat issues | grep -e LOW -e MEDIUM | wc -l)
    echo " - $LOW_MEDIUM_ISSUES low and medium issues found"

    if [ $LOW_MEDIUM_ISSUES -gt 0 ] ; then
        echo "low_medium_issues=$LOW_MEDIUM_ISSUES" >> $GITHUB_OUTPUT
        echo "has_low_medium_issues=true" >> $GITHUB_OUTPUT
    else
        echo "has_low_medium_issues=false" >> $GITHUB_OUTPUT
    fi

    # Check if HIGH or CRITICAL issues are found (remove count from header)
    HIGH_CRITICAL_ISSUES=$(cat issues | grep -e HIGH -e CRITICAL | wc -l)
    echo " - $HIGH_CRITICAL_ISSUES high and crititcal issues found"

    if [ $HIGH_CRITICAL_ISSUES -gt 0 ] ; then
        echo "high_critical_issues=$HIGH_CRITICAL_ISSUES" >> $GITHUB_OUTPUT
        echo "has_high_critical_issues=true" >> $GITHUB_OUTPUT
    else
        echo "has_high_critical_issues=false" >> $GITHUB_OUTPUT
    fi
}

action_docker_checks
github_folder_checks

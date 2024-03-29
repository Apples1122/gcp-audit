#!/bin/bash

source common-constants.inc
source functions.inc

function hasHTTPLoadBalancer() {
    local HTTP_LOAD_BALANCERS
    local HTTPS_LOAD_BALANCERS
    local TRUE=1
    local FALSE=0
    HTTP_LOAD_BALANCERS=$(gcloud compute target-http-proxies list --quiet --format="json")
    HTTPS_LOAD_BALANCERS=$(gcloud compute target-https-proxies list --quiet --format="json")

    if [[ $HTTP_LOAD_BALANCERS == "[]" && $HTTPS_LOAD_BALANCERS == "[]" ]]; then
        echo "$FALSE"
    else
        echo "$TRUE"
    fi
}

function listCloudArmorPolicies() {
    local PROJECT_DETAILS
    local PROJECT_APPLICATION
    local PROJECT_OWNER
    local CLOUD_ARMOR_POLICIES
    PROJECT_DETAILS=$(gcloud projects describe "$PROJECT_ID" --format="json")
    PROJECT_APPLICATION=$(echo "$PROJECT_DETAILS" | jq -rc '.labels.app')
    PROJECT_OWNER=$(echo "$PROJECT_DETAILS" | jq -rc '.labels.adid')
    CLOUD_ARMOR_POLICIES=$(gcloud compute security-policies list --format="json")

    if [[ $DEBUG == "True" ]]; then
        debugCloudArmorPolicies
    fi

    if [[ $CLOUD_ARMOR_POLICIES == "[]" ]]; then
        if [[ $CSV == "True" ]]; then
            echo "\"$PROJECT_ID\", \"$PROJECT_APPLICATION\", \"$PROJECT_OWNER\" \"No Policy\",\"\",\"\",\"\""
        else
            echo "No Cloud Armor policies found for project $PROJECT_ID"
            echo "$BLANK_LINE"
        fi
        return
    fi

    echo "$CLOUD_ARMOR_POLICIES" | jq -r -c '.[]' | while IFS='' read -r POLICY; do
        local CLOUD_ARMOR_POLICY_NAME
        local CLOUD_ARMOR_POLICY_DDOS_PROTECTION_ENABLED
        local CLOUD_ARMOR_POLICY_RULES
        CLOUD_ARMOR_POLICY_NAME=$(echo "$POLICY" | jq -rc '.name')
        CLOUD_ARMOR_POLICY_DDOS_PROTECTION_ENABLED=$(echo "$POLICY" | jq -rc '.adaptiveProtectionConfig.layer7DdosDefenseConfig.enable')
        CLOUD_ARMOR_POLICY_RULES=$(echo "$POLICY" | jq -rc '.rules')

        if [ "$CLOUD_ARMOR_POLICY_DDOS_PROTECTION_ENABLED" = true ]; then
            echo "DDoS protection is enabled."
        else
            echo "VIOLATION:DDoS protection is not enabled."
        fi

        if [[ $CSV == "True" ]]; then
            echo "$CLOUD_ARMOR_POLICY_RULES" | jq -r -c '.[]' | while IFS='' read -r RULE; do
                local RULE_ACTION
                local RULE_DESCRIPTION
                local RULE_MATCH
                RULE_ACTION=$(echo "$RULE" | jq -rc '.action')
                RULE_DESCRIPTION=$(echo "$RULE" | jq -rc '.description')
                RULE_MATCH=$(echo "$RULE" | jq -rc '.match')
                echo "\"$PROJECT_ID\", \"$PROJECT_APPLICATION\", \"$PROJECT_OWNER\", \"$CLOUD_ARMOR_POLICY_NAME\",\"$RULE_DESCRIPTION\",\"$RULE_ACTION\",\"$RULE_MATCH\""
            done
        else
            echo "Project: $PROJECT_ID"
            echo "Application: $PROJECT_APPLICATION"
            echo "Owner: $PROJECT_OWNER"
            echo "Cloud Armor Policy Name: $CLOUD_ARMOR_POLICY_NAME"
            echo "$CLOUD_ARMOR_POLICY_RULES" | jq -r -c '.[]' | while IFS='' read -r RULE; do
                local RULE_ACTION
                local RULE_DESCRIPTION
                local RULE_MATCH
                RULE_ACTION=$(echo "$RULE" | jq -rc '.action')
                RULE_DESCRIPTION=$(echo "$RULE" | jq -rc '.description')
                RULE_MATCH=$(echo "$RULE" | jq -rc '.match')
                echo "$BLANK_LINE"
                echo "Rule Description: $RULE_DESCRIPTION"
                echo "Rule Action: $RULE_ACTION"
                echo "Rule Match: $RULE_MATCH"
                echo "Cloud Armor Policy DDos Protection Enabled: CLOUD_ARMOR_POLICY_DDOS_PROTECTION_ENABLED: $CLOUD_ARMOR_POLICY_DDOS_PROTECTION_ENABLED"
            done
            echo "$BLANK_LINE"
        fi
    done
}

function debugCloudArmorPolicies() {
    echo "Cloud Armor Policies (JSON): $CLOUD_ARMOR_POLICIES"
    echo "$BLANK_LINE"
}

function debugProjects() {
    echo "Projects (JSON): $PROJECTS"
    echo "$BLANK_LINE"
}

function printCSVHeaderRow() {
    echo "\"PROJECT_ID\", \"PROJECT_APPLICATION\", \"PROJECT_OWNER\", \"CLOUD_ARMOR_POLICY_NAME\",\"RULE_DESCRIPTION\",\"RULE_ACTION\",\"RULE_MATCH\""
}

declare DEBUG="False"
declare CSV="False"
declare PROJECT_ID=""
declare PROJECTS=""
declare HELP
HELP=$(cat << EOL

    $0 [-p, --project PROJECT] [-c, --csv] [-d, --debug] [-h, --help]
EOL
)

for arg in "$@"; do
    shift
    case "$arg" in
    "--help") set -- "$@" "-h" ;;
    "--debug") set -- "$@" "-d" ;;
    "--csv") set -- "$@" "-c" ;;
    "--project") set -- "$@" "-p" ;;
    *) set -- "$@" "$arg" ;;
    esac
done

while getopts "hdcip:" option; do
    case "${option}" in
    p) PROJECT_ID=${OPTARG} ;;
    d) DEBUG="True" ;;
    c) CSV="True" ;;
    h)
        echo "$HELP"
        exit 0
        ;;
    esac
done

declare PROJECTS
PROJECTS=$(get_projects "$PROJECT_ID")

if [[ $PROJECTS == "[]" ]]; then
    echo "No projects found"
    echo "$BLANK_LINE"
    exit 0
fi

if [[ $DEBUG == "True" ]]; then
    debugProjects
fi

if [[ $CSV == "True" ]]; then
    printCSVHeaderRow
fi

for PROJECT_ID in $PROJECTS; do

    set_project "$PROJECT_ID"

    if ! api_enabled compute.googleapis.com; then
        if [[ $CSV != "True" ]]; then
            echo "Compute Engine API is not enabled for Project $PROJECT_ID."
        fi
        continue
    fi

    if [[ "$(hasHTTPLoadBalancer)" == "0" ]]; then
        if [[ $CSV != "True" ]]; then
            echo "No HTTP Load Balancers found for project $PROJECT_ID"
            echo "$BLANK_LINE"
        fi
        continue
    fi

    listCloudArmorPolicies
    sleep "$SLEEP_SECONDS"
done

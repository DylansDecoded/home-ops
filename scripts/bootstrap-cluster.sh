#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "${0}")/lib/common.sh"

export ROOT_DIR="$(git rev-parse --show-toplevel)"

# Identify control plane and worker nodes based on node-specific configuration
function identify_node_roles() {
    echo "Identifying node roles"

    if ! nodes=$(talosctl config info --output json 2>/dev/null | jq --exit-status --raw-output '.nodes | join(" ")') || [[ -z "${nodes}" ]]; then
        echo "ERROR: No Talos nodes found"
        exit 1
    fi

    local controlplane_nodes=()
    local worker_nodes=()

    # Check each node's configuration to determine its role
    for node in ${nodes}; do
        local node_config_file="${ROOT_DIR}/talos/nodes/${node}.yaml.j2"

        if [[ ! -f "${node_config_file}" ]]; then
            echo "WARNING: No node-specific configuration found: node=${node}, file=${node_config_file}"
            continue
        fi

        # Use grep to check if the node config contains control plane indicators
        if grep -q "controlplane: true" "${node_config_file}" ||
           grep -q "type: controlplane" "${node_config_file}"; then
            controlplane_nodes+=("${node}")
        else
            worker_nodes+=("${node}")
        fi
    done

    # Return the results
    echo "Control plane nodes identified: ${controlplane_nodes[*]:-none}"
    echo "Worker nodes identified: ${worker_nodes[*]:-none}"

    # Export the arrays for use in other functions
    export CONTROLPLANE_NODES="${controlplane_nodes[*]:-}"
    export WORKER_NODES="${worker_nodes[*]:-}"
}

# Apply the Talos configuration to all the nodes based on their roles
function apply_talos_config() {
    echo "Applying Talos configuration"

    local talos_controlplane_file="${ROOT_DIR}/talos/controlplane.yaml.j2"
    local talos_worker_file="${ROOT_DIR}/talos/worker.yaml.j2"

    if [[ ! -f ${talos_controlplane_file} ]]; then
        echo "ERROR: No Talos machine files found for controlplane, file=${talos_controlplane_file}"
        exit 1
    fi

    # Skip worker configuration if no worker file is found
    if [[ ! -f ${talos_worker_file} ]]; then
        echo "WARNING: No Talos machine files found for worker, file=${talos_worker_file}"
        talos_worker_file=""
    fi

    # First identify node roles
    identify_node_roles

    # Apply control plane configuration to control plane nodes
    if [[ -n "${CONTROLPLANE_NODES}" ]]; then
        echo "Applying control plane configuration to nodes: ${CONTROLPLANE_NODES}"
        for node in ${CONTROLPLANE_NODES}; do
            echo "Applying control plane configuration: node=${node}"

            if ! machine_config=$(bash "${ROOT_DIR}/scripts/render-machine-config.sh" "${talos_controlplane_file}" "${ROOT_DIR}/talos/nodes/${node}.yaml.j2") || [[ -z "${machine_config}" ]]; then
                exit 1
            fi

            echo "Talos node configuration rendered successfully: node=${node}"

            if ! output=$(echo "${machine_config}" | talosctl --nodes "${node}" apply-config --insecure --file /dev/stdin 2>&1);
            then
                if [[ "${output}" == *"certificate required"* ]]; then
                    echo "WARNING: Talos node is already configured, skipping apply of config: node=${node}"
                    continue
                fi
                echo "ERROR: Failed to apply Talos node configuration: node=${node}, output=${output}"
                exit 1
            fi

            echo "Talos control plane configuration applied successfully: node=${node}"
        done
    else
        echo "WARNING: No control plane nodes identified"
    fi

    # Apply worker configuration to worker nodes if worker template exists
    if [[ -n "${talos_worker_file}" && -n "${WORKER_NODES}" ]]; then
        echo "Applying worker configuration to nodes: ${WORKER_NODES}"
        for node in ${WORKER_NODES}; do
            echo "Applying worker configuration: node=${node}"

            if ! machine_config=$(bash "${ROOT_DIR}/scripts/render-machine-config.sh" "${talos_worker_file}" "${ROOT_DIR}/talos/nodes/${node}.yaml.j2") || [[ -z "${machine_config}" ]]; then
                exit 1
            fi

            echo "Talos node configuration rendered successfully: node=${node}"

            if ! output=$(echo "${machine_config}" | talosctl --nodes "${node}" apply-config --insecure --file /dev/stdin 2>&1);
            then
                if [[ "${output}" == *"certificate required"* ]]; then
                    echo "WARNING: Talos node is already configured, skipping apply of config: node=${node}"
                    continue
                fi
                echo "ERROR: Failed to apply Talos node configuration: node=${node}, output=${output}"
                exit 1
            fi

            echo "Talos worker configuration applied successfully: node=${node}"
        done
    elif [[ -z "${talos_worker_file}" ]]; then
        echo "WARNING: No worker template available, skipping worker configuration"
    elif [[ -z "${WORKER_NODES}" ]]; then
        echo "WARNING: No worker nodes identified"
    fi
}

# Bootstrap Talos on a controller node
function bootstrap_talos() {
    echo "Bootstrapping Talos"

    local bootstrapped=true

    # Use a control plane node for bootstrapping
    if [[ -z "${CONTROLPLANE_NODES:-}" ]]; then
        echo "ERROR: No control plane nodes identified for bootstrapping"
        exit 1
    fi

    # Select the first control plane node for bootstrapping
    local controller
    controller=$(echo "${CONTROLPLANE_NODES}" | awk '{print $1}')

    echo "Talos controller selected for bootstrap: controller=${controller}"

    until output=$(talosctl --nodes "${controller}" bootstrap 2>&1); do
        if [[ "${bootstrapped}" == true && "${output}" == *"AlreadyExists"* ]]; then
            echo "Talos is bootstrapped: controller=${controller}"
            break
        fi

        # Set bootstrapped to false after the first attempt
        bootstrapped=false

        echo "Talos bootstrap failed, retrying in 10 seconds...: controller=${controller}"
        sleep 10
    done
}

# Fetch the kubeconfig from a controller node
function fetch_kubeconfig() {
    echo "Fetching kubeconfig"

    # Use a control plane node to fetch kubeconfig
    if [[ -z "${CONTROLPLANE_NODES:-}" ]]; then
        echo "ERROR: No control plane nodes identified for fetching kubeconfig"
        exit 1
    fi

    # Select the first control plane node
    local controller
    controller=$(echo "${CONTROLPLANE_NODES}" | awk '{print $1}')

    echo "Talos controller selected for kubeconfig fetch: controller=${controller}"

    if ! talosctl kubeconfig --nodes "${controller}" --force --force-context-name main "$(basename "${KUBECONFIG}")" &>/dev/null; then
        echo "ERROR: Failed to fetch kubeconfig"
        exit 1
    fi

    echo "Kubeconfig fetched successfully"
}

# Talos requires the nodes to be 'Ready=False' before applying resources
function wait_for_nodes() {
    echo "Waiting for nodes to be available"

    # Skip waiting if all nodes are 'Ready=True'
    if kubectl wait nodes --for=condition=Ready=True --all --timeout=10s &>/dev/null; then
        echo "Nodes are available and ready, skipping wait for nodes"
        return
    fi

    # Wait for all nodes to be 'Ready=False'
    until kubectl wait nodes --for=condition=Ready=False --all --timeout=10s &>/dev/null; do
        echo "Nodes are not available, waiting for nodes to be available. Retrying in 10 seconds..."
        sleep 10
    done
}

# Resources to be applied before the helmfile charts are installed
function apply_resources() {
    echo "Applying resources"

    local -r resources_file="${ROOT_DIR}/bootstrap/resources.yaml.j2"

    if ! output=$(render_template "${resources_file}") || [[ -z "${output}" ]]; then
        exit 1
    fi

    if echo "${output}" | kubectl diff --filename - &>/dev/null; then
        echo "Resources are up-to-date"
        return
    fi

    if echo "${output}" | kubectl apply --server-side --filename - &>/dev/null; then
        echo "Resources applied"
    else
        echo "ERROR: Failed to apply resources"
        exit 1
    fi
}

# Disks in use by rook-ceph must be wiped before Rook is installed
function wipe_rook_disks() {
    echo "Wiping Rook disks"

    # Skip disk wipe if Rook is detected running in the cluster
    # TODO: Is there a better way to detect Rook / OSDs?
    if kubectl --namespace rook-ceph get kustomization rook-ceph &>/dev/null; then
        echo "WARNING: Rook is detected running in the cluster, skipping disk wipe"
        return
    fi

    if ! nodes=$(talosctl config info --output json 2>/dev/null | jq --exit-status --raw-output '.nodes | join(" ")') || [[ -z "${nodes}" ]]; then
        echo "ERROR: No Talos nodes found"
        exit 1
    fi

    echo "Talos nodes discovered: nodes=${nodes}"

    # Wipe disks on each node that match the ROOK_DISK environment variable
    for node in ${nodes}; do
        if ! disks=$(talosctl --nodes "${node}" get disk --output json 2>/dev/null \
            | jq --exit-status --raw-output --slurp '. | map(select(.spec.model == env.ROOK_DISK) | .metadata.id) | join(" ")') || [[ -z "${nodes}" ]];
        then
            echo "ERROR: No disks found: node=${node}, model=${ROOK_DISK}"
            exit 1
        fi

        echo "Talos node and disk discovered: node=${node}, disks=${disks}"

        # Wipe each disk on the node
        for disk in ${disks}; do
            if talosctl --nodes "${node}" wipe disk "${disk}" &>/dev/null; then
                echo "Disk wiped: node=${node}, disk=${disk}"
            else
                echo "ERROR: Failed to wipe disk: node=${node}, disk=${disk}"
                exit 1
            fi
        done
    done
}

# Apply Helm releases using helmfile
function apply_helm_releases() {
    echo "Applying Helm releases with helmfile"

    local -r helmfile_file="${ROOT_DIR}/bootstrap/helmfile.yaml"

    if [[ ! -f "${helmfile_file}" ]]; then
        echo "ERROR: File does not exist: file=${helmfile_file}"
        exit 1
    fi

    if ! helmfile --file "${helmfile_file}" apply --hide-notes --skip-diff-on-install --suppress-diff --suppress-secrets; then
        echo "ERROR: Failed to apply Helm releases"
        exit 1
    fi

    echo "Helm releases applied successfully"
}

function main() {
    check_env KUBECONFIG KUBERNETES_VERSION ROOK_DISK TALOS_VERSION
    check_cli helmfile jq kubectl kustomize minijinja-cli op talosctl yq

    if ! op user get --me &>/dev/null; then
        echo "ERROR: Failed to authenticate with 1Password CLI"
        exit 1
    fi

    # Bootstrap the Talos node configuration
    apply_talos_config
    bootstrap_talos
    fetch_kubeconfig

    # Apply resources and Helm releases
    wait_for_nodes
    wipe_rook_disks
    apply_resources
    apply_helm_releases

    echo "Congrats! The cluster is bootstrapped and Flux is syncing the Git repository"
}

main "$@"

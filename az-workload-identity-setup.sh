#!/bin/bash

export CREATE_RESOURCE_GROUP=true
export CREATE_AKS=true

## Replace values with your own data

export RESOURCE_GROUP="<>"
export LOCATION="<>"
export SERVICE_ACCOUNT_NAMESPACE="<>"
export SERVICE_ACCOUNT_NAME="workload-identity-sa"
export IDENTITY_NAME="user-identity-name"
export FEDERATED_IDENTITY_CREDENTIAL_NAME="federated-identity-name"
export KEYVAULT_NAME="keyvault-name"
export KEYVAULT_SECRET_NAME="test-secret"

export SUBSCRIPTION="$(az account show --query id --output tsv)"

## Create Resource Group
if [[ "${CREATE_RESOURCE_GROUP}" == "true" ]]; then
  az group create --name "${RESOURCE_GROUP}" --location "${LOCATION}"
fi


## Create AKS
if [[ "${CREATE_AKS}" == "true" ]]; then
  az aks create -g "${RESOURCE_GROUP}" -n myAKSCluster --enable-oidc-issuer --enable-workload-identity --generate-ssh-keys
else 
  az aks update -g "${RESOURCE_GROUP}" -n myAKSCluster --enable-oidc-issuer --enable-workload-identity
fi

## Create User Assigned Identity
az identity create --name "${IDENTITY_NAME}" --resource-group "${RESOURCE_GROUP}" --location "${LOCATION}" --subscription "${SUBSCRIPTION}"

## Get AKS OIDC Issuer URL 
export AKS_OIDC_ISSUER="$(az aks show -n myAKSCluster -g "${RESOURCE_GROUP}" --query "oidcIssuerProfile.issuerUrl" -o tsv)"


## Create Federated Identity Credential based on the User Assigned Identity
az identity federated-credential create --name ${FEDERATED_IDENTITY_CREDENTIAL_NAME} --identity-name "${IDENTITY_NAME}" --resource-group "${RESOURCE_GROUP}" --issuer "${AKS_OIDC_ISSUER}" --subject system:serviceaccount:"${SERVICE_ACCOUNT_NAMESPACE}":"${SERVICE_ACCOUNT_NAME}" --audience api://AzureADTokenExchange


## Get User Assigned Identity Client ID
export USER_ASSIGNED_CLIENT_ID="$(az identity show --resource-group "${RESOURCE_GROUP}" --name "${IDENTITY_NAME}" --query 'clientId' -o tsv)"

## Assign KeyVault Get Secret Permission to the User Assigned Identity
az keyvault set-policy --name "${KEYVAULT_NAME}" --secret-permissions get --spn "${USER_ASSIGNED_CLIENT_ID}"

az keyvault secret set --vault-name "${KEYVAULT_NAME}" --name "${KEYVAULT_SECRET_NAME}" --value "Hello\!"


## Login to AKS
az aks get-credentials -n myAKSCluster -g "${RESOURCE_GROUP}"

## Create Service Account
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: "${USER_ASSIGNED_CLIENT_ID}"
  name: "${SERVICE_ACCOUNT_NAME}"
  namespace: "${SERVICE_ACCOUNT_NAMESPACE}"
EOF

## Create Pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: your-pod
  namespace: "${SERVICE_ACCOUNT_NAMESPACE}"
  labels:
    azure.workload.identity/use: "true"  # Required, only the pods with this label can use workload identity
spec:
  serviceAccountName: "${SERVICE_ACCOUNT_NAME}"
  containers:
    - image: <your image>
      name: <containerName>
EOF


#!/bin/bash -xe

export RELEASE=${RELEASE:-aut-op}
export NAMESPACE=${NAMESPACE:-default}
export HELM=${HELM:-helm}

ISINSTALL=0
STATUS=$($HELM list $RELEASE -q)
if [ "$STATUS" = "" ]
then
  # install chart
  gostint/init/vault-preinit.sh
  helm install gostint/ \
    --name $RELEASE \
    --namespace $NAMESPACE
  ISINSTALL=1
else
  helm upgrade $RELEASE gostint/ \
    --namespace $NAMESPACE
fi

gostint/init/vault-init.sh

# pods will auto unseal, see postStart lifecycle hook
# so wait for each pod to be unsealed itself
PODS=$(
  kubectl get pods \
    -l app=vault,release=$RELEASE \
    -n $NAMESPACE \
    | awk '{if(NR>1)print $1}'
)
for POD in $PODS
do
  (
    for i in $(seq 1 200)
    do
      SEALED_STATUS=$(
        kubectl exec \
          -n $NAMESPACE $POD \
           -c vault \
          -- sh -c "vault status --tls-skip-verify | awk '/^Sealed/ { print \$2; }'" \
          2>&1
      )
      if [ "$SEALED_STATUS" == "false" ]
      then
        exit 0
      fi
      sleep 5
    done
    echo "ERROR: Timed out waiting for Vault POD $POD to unseal itself" >&2
    exit 1
  ) || exit 1
done

if [ $ISINSTALL == 1 ]
then
  # TODO: make idempotent
  gostint/init/gostint-init.sh || exit 1
  gostint/init/ingress-init.sh || exit 1
fi

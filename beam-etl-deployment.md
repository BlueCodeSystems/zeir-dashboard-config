# Beam ETL

## Ensure prerequisites

* A kubernetes namespace with Amazon Elastic Container Registry (ECR) access: see [aws-ecr-credential](./aws_ecr_credential.md)

* A shell with:

  * [Install kubectl utility](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
  * [Install kops utility](https://kubernetes.io/docs/setup/production-environment/tools/kops/)
  * [Install helm utility](https://helm.sh/docs/intro/install/)
  * [Install helm-secrets extension](https://github.com/zendesk/helm-secrets)

```sh
$ mkdir helm/releases/<cluster>/<client>-<env>-beam-etl-[<source>-]<entity>
$ cd helm/releases/<cluster>/<client>-<env>-beam-etl-[<source>-]<entity>
$ echo "# $(basename $(pwd))" > README.md && \
    echo 'See release docs [here](../../../../release-docs/beam-etl.md)' >> README.md
```

Source some shared cluster namespace variables:

```sh
$ cat ../.nsenv
export KOPS_CONFIG_BUCKET=s3://clusters.<>.k8s.onalabs.org
export KOPS_CONFIG_NAME=<>.k8s.onalabs.org
export K8S_NAMESPACE=<>
$ source ../.nsenv
```

## Ensure an AWS MFA session:

In order to use helm secrets it is required to login to an AWS MFA session with a 2FA device of some kind:

```sh
$ echo $AWS_SESSION_TOKEN

$ echo $AWS_IAM_MFA_DEVICE_ARN
arn:aws:iam::<>:user/<>
$ source ../../../../scripts/aws_2fa_session.sh
Enter the 2FA code for arn:aws:iam::<>:user/<> (arn:aws:iam::<>:mfa/<>):
...
```

> NOTE that it's not possible to login to a new MFA session when one is active - you must reset your credentials
> back to a profile with `aws_profile_identity.sh`

## Connect to K8s cluster

```sh
$ kops --state $KOPS_CONFIG_BUCKET export kubecfg $KOPS_CONFIG_NAME
kops has set your kubectl context to <>.k8s.onalabs.org
$ kubectl cluster-info
Kubernetes master is running at https://api.<>.k8s.onalabs.org
KubeDNS is running at https://api.<>.k8s.onalabs.org/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
...
```

## Modify Beam ETL parameters

```sh
$ helm secrets dec secrets.yaml
< do stuff to secrets.yaml.dec >
$ helm secrets enc secrets.yaml
```

## Install/Update Beam ETL

This command installs the helm chart with the values/secrets in [values.yaml](./values.yaml)/[secrets.yaml](./secrets.yaml) in the loaded namespace:

```sh
$ echo Installing "$(basename $(pwd))" to "$(kubectl cluster-info | grep master | awk '{print $6}')" && \
  helm secrets upgrade --values=values.yaml --values=secrets.yaml \
    --install "$(basename $(pwd))" --namespace $K8S_NAMESPACE ../../../../charts/beam-etl
```

> NOTE: the long name gets close to 63 char limits for the pod - make sure the directory / release name contains `beam-etl` as otherwise that suffix  will get appended to the pod names

After a few moments, try:
```sh
$ kubectl --namespace $K8S_NAMESPACE describe pod "$(basename $(pwd))-0"
...
$ kubectl --namespace $K8S_NAMESPACE logs "$(basename $(pwd))-0"
```

## Uninstall Beam ETL

```sh
$ helm uninstall "$(basename $(pwd))" --namespace $K8S_NAMESPACE
```

To also clear ETL state:

```sh
$ helm uninstall "$(basename $(pwd))" --namespace $K8S_NAMESPACE && kubectl delete pvc var-beam-etl-$(basename $(pwd))-0 --namespace $K8S_NAMESPACE
```

## Monitoring Beam ETLs

All ETL activity is logged to `stdout` and collected via the standard k8s logging infrastructure.  Currently our `mango.dev` and `orange.prod` clusters push all `beam-etl` pod logs to [Graylog](https://graylog.onalabs.org/search), which allows searching across any [ETL logs](https://graylog.onalabs.org/search?rangetype=relative&q=kubernetes_container_name%3Abeam-etl&relative=604800) for any kind of messages.  This happens automatically, there's no configuration required and logs should be available soon after you've run the helm install or update.

There's also a K8s [beam-etl dashboard](https://graylog.onalabs.org/dashboards/5fc8cb01904193324537617a) available with helpful charts based on generic queries.

For more information about long-term monitoring of Beam ETLs including sample log messages, see the [docs here](https://github.com/onaio/beam-etl/blob/master/docs/LongRunningEtls.md). 


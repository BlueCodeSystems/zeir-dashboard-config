# helm-beam-etl-chart

Helm chart to deploy a beam-etl pod to k8n.

## Example values

There are two ways to deploy beam-etls - via raw command-line `args` or via a `pipeline` object.  Usually the `pipeline` object should be used, except
in the case of new or experimental features. 

To deploy a beam-etl using the `pipeline` options:

```yaml
pipeline:

  runner:
    # v1.1 only!
    statsIntervalSecs: 60

  source:
    class: OpenSrpRestSourcePipe
    baseUri: https://hostname.org/opensrp/rest
    entityType: event
  
  transforms:
    - class: JsonStreamTransformPipe
      joltUrl: config.json#/event/transform
      jsonSchemaUrl: config.json#/event/schema
  
  sink:
    class: JsonStreamToJpaSinkPipe
    jdbcUrl: jdbc:postgresql:postgis://postgres.hostname.org:5432/project_db

env:
  CONFIG_URL: github+commit+https://github.com/onaio/etl-configs/blob/48ac8b189/project/config.json
  
# Usually these should be in a separate secrets.yaml file
envSecrets:
  GITHUB_OAUTH_TOKEN: abcde-some-long-token

# Not usually required, but can be changed if needed
# cpu:
  # Units: %vCPU
  # request: 0.125
  # limit: 0.5
# memory:
  # Units: Megabytes
  # USE CAPITAL "M" for MB - lowercase M isn't understood by k8s and G isn't understood by jvm
  # zkJvm: 64M
  # kafkaJvm: 192M
  # jvm: 768M
  # ~4 ETLs per 2GB
  # request: 512M
  # limit: 1024M
# Durable storage
# storage: 3G
# storageClassName:

image:
  tag: <.Chart.appVersion> # Override to change the beam-etl container image used
  registry: <aws id>.dkr.ecr.<aws region>.amazonaws.com
  pullSecret: aws-registry

```

The raw command-line argument version is here:

```yaml
args:
  - --runner=SamzaRunner
  - --durablePath=/var/beam-etl/samza
  #
  - --sourceClass=OpenSrpRestSourcePipe
  - --baseUri=https://hostname.org/opensrp/rest
  - --entityType=event
  #
  - --transformClass=JsonStreamTransformPipe
  - --joltUrl=config.json#/event/transform
  - --jsonSchemaUrl=config.json#/event/schema
  #
  - --sinkClass=JsonStreamToJpaSinkPipe
  - --jdbcUrl=jdbc:postgresql:postgis://postgres.hostname.org:5432/project_db

... (other options the same)

```

> The chart mounts persistent storage at `/var/beam-etl` - this should generally be where the `--durablePath` points to for the `SamzaRunner`.  Even in the case of a `--kafkaDurable` setting, where all state changes are logged to a remote Kafka cluster, the local RocksDB cache for ETL state should be placed on moderately-durable storage to allow for much faster restart.

## K8n Resources

The `beam-etl` chart creates several resources:

* A `StatefulSet` which ensures the single pod has the same storage when rescheduled across nodes, and also that the storage volume is *not* automatically deleted 

  > This is a bit of future-proofing, as it's possible to run ETLs on a multi-node Samza instance to scale compute resources.  This would require each node have stable storage and networking.  For now, it's nice to reduce automatic cleanup.

* A stub `Service`, not really required right now but required by `StatefulSet`

  > Also a bit of future-proofing - it's probably very useful to expose a JVM / ETL stats server for progress tracking. 

* A `Secret` to hold sensitive credentials for the ETL


## Testing and Quickstart

To ensure the `beam-etl` chart is working properly, integration tests (using [KIND](https://kind.sigs.k8s.io/docs/user/quick-start)) have been developed in [Go](https://golang.org/).

### Prerequisites

- Linux
- Docker
- Go v1.13 or compatible
  - One way of managing this locally and avoid polluting other projects is to use [goenv](https://github.com/syndbg/goenv)

### Bootstrapping a KIND cluster

To make it easy to play with Kubernetes, a script is provided in `test/kind/ensure_kind_cluster.sh` which:

1. Installs isolated versions of `kubectl`, `kind`, and `helm`
2. Starts a `kind` cluster using the available Docker tools
3. Installs an isolated `kind` .kube/config, accessible via a `test/kind/env.sh` wrapper script

```bash
$ test/kind/ensure_kind_cluster.sh
...
KIND clusters:
kind

Cluster info:
Kubernetes master is running at https://127.0.0.1:37787
KubeDNS is running at https://127.0.0.1:37787/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
...
```

### Bootstrapping ECR Credentials

To use the private `onaio/beam-etl` images, you must ensure login credentials in the K8n cluster.  To do this we use the `architectminds/aws-ecr-credential` helm chart.

As a helper for KIND, stage, and production K8n deployments, the `scripts/ensure_ecr_on_k8n.sh` script can be used:

```bash
$ export AWS_ACCESS_KEY_ID=<value from .aws/credentials>
$ export AWS_SECRET_ACCESS_KEY=<value from .aws/credentials>
$ export DOCKER_REGISTRY=<aws id>.dkr.ecr.<aws region>.amazonaws.com
$ export DOCKER_REGISTRY_SECRET_NAME=aws-registry
$ test/kind/env.sh scripts/ensure_ecr_on_k8n.sh $DOCKER_REGISTRY default
```

> NOTE that the AWS credentials here **must** be user and not session credentials - the `aws-ecr-credential` helper process needs to periodically refresh
the registry credentials and so can't use a temporary session. 

> NOTE that ECR docker registries are located in particular regions - the registry `aws region` should not be your user default but the region of the registry itself.  The current `onaio/beam-etl` ECR registry is `447036922786.dkr.ecr.eu-central-1.amazonaws.com`.

If things worked correctly, you should be able to list secrets and see an `aws-registry` secret created:

```bash
$ test/kind/env.sh kubectl get secrets
...
aws-registry                                                         kubernetes.io/dockerconfigjson        1      4h50m
...
```

### Release `example` ETL

Then, using the registry, you should be able to run the default, do-nothing ETL on KIND:

```
$ test/kind/env.sh helm install example . \
    --set image.registry=$DOCKER_REGISTRY,image.pullSecret=$DOCKER_REGISTRY_SECRET_NAME
...
NAME: example
LAST DEPLOYED: Thu Nov 12 14:45:23 2020
NAMESPACE: default
STATUS: deployed
...

$ test/kind/env.sh kubectl get all
NAME                         READY   STATUS    RESTARTS   AGE
pod/example-beam-etl-0       1/1     Running   0          10s

NAME                           TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
service/example-beam-etl       ClusterIP   None         <none>        <none>    10s
service/kubernetes             ClusterIP   10.96.0.1    <none>        443/TCP   3h55m

NAME                                    READY   AGE
statefulset.apps/example-beam-etl       1/1     10s
```

### Integration tests via KIND

Testing of the chart uses the [Terratest](https://terratest.gruntwork.io/) infrastructure - this is basically a test library in Go that provides fixtures to manipulate kubernetes clusters and helm deployments.

> Helm has built-in smoke tests run on every deployment, but does not provide support for integration tests to ensure that sample deployments behave as expected.

To initialize the test module, run:

```bash
$ (cd test; go mod download)
```

Next, we need to install the AWS credentials to our kind cluster if we haven't already (see above).

Using the isolated KIND environment, we can now run our integration tests (using the same environment variables from above):

```bash
$ (cd test; kind/env.sh go test)
TestBasicChartDeploy 2020-11-12T14:49:23+03:00 logger.go:66: Running command helm with args [install --set storage=128m test-pxuufx /home/gstuder/Workspaces/Ona/helm-beam-etl-chart]
...
TestBasicChartDeploy 2020-11-12T14:49:33+03:00 logger.go:66: Running command helm with args [delete test-pxuufx]
TestBasicChartDeploy 2020-11-12T14:49:34+03:00 logger.go:66: release "test-pxuufx" uninstalled
PASS
ok  	github.com/onaio/helm-beam-etl-chart/test	10.958s
```




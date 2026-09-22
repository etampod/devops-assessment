# Goal 2

## Code review — DevOps Engineer Homework

This review is of the incomplete project as received, it lists the five most important fixes.

### 1. Helm Service and Ingress don't select the application

The Deployment labels pods `app: myapp`. The Service selector is `app: myapps`, and the Ingress backend service name is `homeworks`. Kubernetes will create a Service with no Endpoints and an Ingress that points at a Service that does not exist.

**Fix:** Use one naming scheme (Helm `fullname` + shared selector labels) on the Deployment, Service, and Ingress. Template the Ingress backend from the Service name and Service port.

### 2. Container, Service, and values don't match on the listen port

The `values.yaml` has `service.port: 8080`. The Deployment `containerPort` is `5000`. The Service `targetPort` is `8080` while its `port` is `80`. Even after the selector typo is fixed, kube-proxy still sends traffic to a port the process is not listening on.

**Fix:** Pick a single port (8080) and use it in the application, Dockerfile `EXPOSE`, `containerPort`, Service `targetPort`, and Ingress backend. Drive those values from `values.yaml` instead of hardcoding them.

### 3. Terraform's configuration doesn't parse and can't find the chart

The `helm_release` sets `image.tag` to an empty `value =`, so HCL is invalid. The `environment` is set to unquoted `prod`, which Terraform treats as a resource reference. The chart path is `../helm/homework` while the chart lives in `../helm` (`Chart.yaml` has name `myapp`). Variables `namespace`, `environment`, and `image_tag` are declared and never used; the namespace is hardcoded as `production`.

**Fix:** Quote string values, pass `var.image_tag` / `var.environment` / `var.namespace` into the release, point `chart` in the actual chart directory, add `required_providers` for `hashicorp/kubernetes` and `hashicorp/helm`, and don't name a local Kind/Minikube namespace `production`.

### 4. There isn't any application image to deploy

The `app/` only contains a requirements README. There isn't any Python/Go source, no Dockerfile, and no dependency lock. Helm has nothing that can listen on `/health`.

**Fix:** Implement the documented HTTP service, add a Dockerfile that exposes 8080, and inject `ENVIRONMENT`. Keep `/config` in memory.

### 5. GitLab CI is empty 

The pipeline stages exist, but both jobs have only `echo`. There are no tests, no image build, no registry push, no `helm lint` / `terraform validate`, and no deploy credentials.

**Fix:** Add `test`, `validate`,`build` and `deploy` stages. Gate deploy on the default branch. Use `IfNotPresent` locally-

---

Honourable mentions: add `/health` probes, a non-root `securityContext`, and stop hardcoding `metadata.name: myapp` so two Helm releases can coexist.

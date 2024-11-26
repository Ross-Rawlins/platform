# Jembi Platform

OpenHIM platform is an easy way to set up, manage and operate a Health Information Exchange (HIE). Specifically, it is the following:

- A toolbox of open-source tools, grouped into packages, that are used within an HIE.
- The glue that ties these tools together. These are often in the form of OpenHIM mediators which are just microservices that talk to OpenHIM.
- A CLI tool to deploy and manage these packages.

> [!NOTE]
> 📚 Check out the [OpenHIM platform documentation](https://jembi.gitbook.io/openhim-platform) for more information!

## Tech Used

- Instant OpenHIE
- Docker
- Golang (cli dev)
- Terraform (remote cluster setup)
- Ansible (remote cluster setup)

## Quick Start for devs (local single node)

1. If running into an error `invalid mount config for type "bind": bind source path does not exist: /tmp/logs` on running the CLI binary, run the following command: `sudo mkdir -p /tmp/logs/`.
1. `./build-image.sh` - builds the platform image
1. Initialise Docker Swarm mode: `docker swarm init`
1. Run `go cli` binary to launch the project:

    - **Linux**. From terminal run: `./instant-linux` with your selected arguments. A list of available arguments can be found in the help menu by running `./instant-linux help`
    - Mac. From terminal run: `./instant-macos` with your selected arguments. A list of available arguments can be found in the help menu by running `./instant-macos help`
        > Warning: Mac has an issue with the binary as it views the file as a security risk. See [this article](https://www.lifewire.com/fix-developer-cannot-be-verified-error-5183898) to bypass warning
    - Windows. Double click: `platform.exe` (Windows users will need to use a release version below 2.0.0)

## Quick Start for devs (remote cluster)

To set up a remote cluster environment, see [readme](https://github.com/jembi/cloud/blob/main/aws/mercury-team/README.md) in the [cloud repo](https://github.com/jembi/cloud).

1. Ensure that you have the latest instant repository checked out in the same folder that this repo is in.
1. `./build-image.sh` - builds the platform image
1. Add `.env.prod` file with your remote env vars option set.

    > Each Package contains a `metadata.json` file which lists the configurable Env vars and their default values

1. Run `go cli` binary to launch the project (*Make sure to add the `DOCKER_HOST` variable indicating your **lead Swarm manager***, i.e. DOCKER_HOST=ssh://{lead_ip} ./instant-linux):

1. Check the current cli version in `./get-cli.sh` and run to download the binaries. This script can be run with the OS as the first parameter to download only the binary for your prefered OS.
    - **Linux**. From terminal run: `./instant-linux` with your selected arguments. A list of available arguments can be found in the help menu by running `./instant-linux help`
    - Mac. From terminal run: `./instant-macos` with your selected arguments. A list of available arguments can be found in the help menu by running `./instant-macos help`
        > Warning: Mac has an issue with the binary as it views the file as a security risk. See [this article](https://www.lifewire.com/fix-developer-cannot-be-verified-error-5183898) to bypass warning
    - Windows. Double click: `platform.exe` (Windows users will need to use a release version below 2.0.0)

## Go Cli Dev

The Go Cli scripts are kept in the [OpenHIE Package Start Kit Repo](https://github.com/openhie/package-starter-kit/tree/main/cli). To make changes to the Cli clone the repo and make your changes in the `cli` directory.

To create new binaries, create a new tag and release and then change the cli version in `./get-cli.sh` in the platform repo and run the script to download the latest.

## Platform Package Dev

The Go Cli runs all services from the `jembi/platform` docker image. When developing packages you will need to build your dev image locally with the following command:

```sh
./build-image.sh
```

As you add new packages to the platform remember to list them in `config.yaml` file. This config file controls what packages the GO CLI can launch.

For logging all output to a file, ensure that you have created the file and it has the required permissions to be written to.
The default log file with it's path is set in `.env.local` in `BASHLOG_FILE_PATH`. 
The logPath property in the `config.yml` is used to create a bind mount for the logs to be stored on the host.

## Resource Allocations

The resource allocations for each service can be found in each service's respective docker-compose.yml file under `deploy.resources`. The field `reservations` specifies reserved resources for that service, per container. The field `limits` specifies that maximum amount of resources that can be used by that service, per container.

Each service's resource allocations can be piped into their .yml file through environment variables. Look at the .yml files for environment variable names per service.

### Notes on Resource Allocations

- CPU allocations are specified as a portion of the total number of cores on the host system, i.e., a CPU limit of `2` in a `6-core` system is an effective limit of `33.33%` of the CPU, and a CPU limit of `6` in a `6-core` system is an effective limit of `100%` of the CPU.
- Memory (RAM) allocations are specified as a number followed by their multiplier, i.e., 500M, 1G, 10G, etc.
- Be wary of allocating CPU limits to ELK Stack services. These seem to fail with CPU limits and their already implemented health checks.
- Take note to not allocate less memory to ELK Stack services than their JVM heap sizes.
- Exit code 137 indicates an out-of-memory failure. When running into this, it means that the service has been allocated too little memory.

## Build multi-platform docker images
It's essential to make sure that any docker image should be available for multiple platforms : AMD, ARM, ... (not only linux, but MacOS as well). To do so you can follow the steps below :
1. Create your own custom builder by running `docker buildx create --name mycustombuilder --driver docker-container --bootstrap`
2. Ask docker to use this new builder for future builds by running `docker buildx use mycustombuilder`
3. Inspect buildx to see if docker has indeed switched builders to the new one you asked it to use by running `docker buildx inspect`
4. Then you can perform the build and push, for example : `docker buildx build --platform linux/amd64,linux/arm64 --push -t jembi/hapi:v7.0.3-wget  .`

## Tests

Tests are located in `/test`

### Cucumber

Tests that execute platform-linux with parameters and observe docker to assert expected outcomes

View `/test/cucumber/README.md` for more information

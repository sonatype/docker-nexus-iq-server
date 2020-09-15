<!--

  Copyright (c) 2017-present Sonatype, Inc.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

-->

# Sonatype Nexus IQ Server Docker: sonatype/nexus-iq-server

A Dockerfile for Sonatype Nexus IQ Server, based on [Red Hat Universal Base Image](https://www.redhat.com/en/blog/introducing-red-hat-universal-base-image).

* [Migration](#migration)
* [Runtime Server Configuation](#runtime-server-configuration)
* [Persistent Data](#persistent-data)
* [Running](#running)
* [Product License Installation](#product-license-installation)
* [Building the Nexus IQ Server image](#building-the-nexus-iq-server-image)
  * [Customizing the Default Built config.yml](#customizing-the-default-built-configyml)
* [Testing the Dockerfile](#testing-the-dockerfile)
* [Red Hat Certified Image](#red-hat-certified-image)
* [Chef Solo for Runtime and Application](chef-solo-for-runtime-and-application)
* [Project License](#project-license)

## Migration
### Upgrading from Version 68 or Earlier to Version 69 or Later
Version 1.69.0 of the Docker image changed the base image from CentOS to Red Hat UBI (Universal Base Image). 
As a result, the UID of the `nexus` user has changed. If you use this image with a persistent data volume you will need 
to run the following for your server to start up successfully:
```
docker run -it -u=0 -v sonatype-work:/sonatype-work sonatype/nexus-iq-server:1.69.0 chown -R nexus:nexus /sonatype-work
```
This will start up a 1.69.0 IQ server container with root as the user, allowing it to chown the sonatype-work directory 
and its files to the correct nexus user.

## Runtime Server Configuration

Installation of Nexus IQ Server application is to `/opt/sonatype/nexus-iq-server`.

By default, the IQ Server reads its [main configuration file](https://help.sonatype.com/iqserver/configuring/config.yml) from within the image at `/etc/nexus-iq-server/config.yml`.

There is an environment variable `JAVA_OPTS` that passes JVM arguments to the java command that launches IQ server.

This environment variable can be adjusted at runtime:

```
$ docker run -d -p 8070:8070 -p 8071:8071 --name nexus-iq-server -e JAVA_OPTS="-Doption=value" sonatype/nexus-iq-server
```

Further, you can [customize parts of the default config.yml settings by using Java system properties](https://help.sonatype.com/iqserver/configuring/advanced-server-configuration) defined inside the environment variable.

Example: To customize the logging level that IQ Server will use:

```
$ docker run -d -p 8070:8070 -p 8071:8071 --name nexus-iq-server -e \
  JAVA_OPTS="-Ddw.logging.level=TRACE" sonatype/nexus-iq-server
```

## Persistent Data

There are two general approaches to handling persistent storage requirements
with Docker. See [Managing Data in Containers](https://docs.docker.com/engine/tutorials/dockervolumes/)
for additional information.

  1. *Use a data volume*.  Since data volumes are persistent
  until no containers use them, a volume can be created specifically for
  this purpose.  This is the recommended approach.  

  ```
  $ docker volume create --name sonatype-work
  $ docker run -d -p 8070:8070 -p 8071:8071 --name nexus-iq-server -v sonatype-work:/sonatype-work sonatype/nexus-iq-server
  ```

  2. *Mount a host directory as the volume*.  This is not portable, as it
  relies on the directory existing with correct permissions on the host.
  However it can be useful in certain situations where this volume needs
  to be assigned to certain specific underlying storage.  

  ```
  $ mkdir /some/dir/sonatype-work
  $ docker run -d -p 8070:8070 -p 8071:8071 --name nexus-iq-server -v /some/dir/sonatype-work:/sonatype-work sonatype/nexus-iq-server
  ```
  
## Running

To run with ports 8070 (web UI) and 8071 (admin port) use:

    docker run -d -p 8070:8070 -p 8071:8071 --name nexus-iq-server sonatype/nexus-iq-server

or to let docker assign available ports use:

    docker run -d -p 8070 -p 8071 --name nexus-iq-server sonatype/nexus-iq-server

To get the assigned port or check if the server is running use:

    docker ps --filter "name=nexus-iq-server"
    
## Product License Installation

Once running, the IQ Server product license must be installed. This should be done [using the user interface](https://help.sonatype.com/iqserver/installing/iq-server-installation#IQServerInstallation-InstalltheLicense). 

Default admin credentials are: `admin` / `admin123`

### Version 96 or Later
The IQ Server product license is stored in the database and so will survive image restarts as long as the database is
persisted.

### Version 95 or Earlier
The IQ Server product license is stored using Java preferences API. By default, the directory location is already
customized by a Java system property to be under the sonatype-work directory i.e.
`-Djava.util.prefs.userRoot=${SONATYPE_WORK}/javaprefs` so as to survive image restarts.

If customized using `JAVA_OPTS`, the absolute path to user prefs must point to an already created directory readable by the user account owning the process. 

Under the preferences directory, IQ Server will store the installed license file at a path ./com/sonatype/clm/prefs.xml

## Building the Nexus IQ Server image

To build a docker image from the Dockerfile you can use this command:

    docker build --rm=true --tag=sonatype/nexus-iq-server .

The following optional variables can be used when building the image:

- IQ_SERVER_VERSION: Version of Nexus IQ Server
- IQ_SERVER_SHA256: Check hash matches the downloaded IQ Server archive or else fail build. Required if `IQ_SERVER_VERSION` is provided.
- JAVA_URL: Download URL for Oracle JDK
- JAVA_SHA256: Check hash matches the downloaded JDK or else fail build. Required if `JAVA_URL` is provided.
- SONATYPE_WORK: Path to Nexus IQ Server working directory where variable data is stored

### Customizing the Default Built config.yml

The `solo.json.erb` template file can be used to customize the Nexus IQ Server configuration. The
`nexus_iq_server.config` property of this Embedded Ruby template will be rendered and then saved as the Nexus IQ
Server's config.yml. See [IQ Server Configuration](https://help.sonatype.com/iqserver/configuring) for
more details as to what values are supported.

Here is an example of how to set the server and baseUrl sections of the config.yml:

```
  :nexus_iq_server => {
    :version => ENV['IQ_SERVER_VERSION'],
    :checksum => ENV['IQ_SERVER_SHA256'],
    :install_dir => ENV['IQ_HOME'],
    :config => {
      :sonatypeWork => ENV['SONATYPE_WORK'],
      :server => {
        :applicationConnectors => [
          :type => 'https',
          :port => 8443,
          :keyStorePath =>  '/path/to/your/keystore/file',
          :keyStorePassword => 'yourpassword'
        ],
        :adminConnectors => [
          :type => 'https',
          :port => 8471,
          :keyStorePath =>  '/path/to/your/keystore/file',
          :keyStorePassword => 'yourpassword'
        ]
      },
      :baseUrl => 'https://nexus-iq-server.example.com/'
    }
  }
```

## Testing the Dockerfile

We are using `rspec` as test framework. `serverspec` provides a docker backend (see the method `set` in the test code)
 to run the tests inside the docker container, and abstracts away the difference between distributions in the tests
 (e.g. yum, apt,...).

    rspec [--backtrace] spec/Dockerfile_spec.rb

## Red Hat Certified Image

A Red Hat certified container image can be created using Dockerfile.rh which pulls from assets in the red-hat-assets
folder. The image includes additional meta data to conform with Atomic and OpenShift standards, a directory with the
licenses applicable to the software and a man file for help on how to use the software.  It also uses an ENTRYPOINT
script the ensure the running user has access to the appropriate permissions for OpenShift 'restricted' SCC.

## Chef Solo for Runtime and Application

Chef Solo is used to build out the runtime and application layers of the Docker image. The Chef cookbook being used is available
on GitHub at [sonatype/chef-nexus-iq-server](https://github.com/sonatype/chef-nexus-iq-server).

## Project License

Unless noted in their header, files in this GitHub repository are licensed under the [Apache v2 license](LICENSE)

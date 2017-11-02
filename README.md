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

A Dockerfile for Sonatype Nexus IQ Server, base on CentOS.

* [Running](#running)
* [Building the Nexus IQ Server image](#building-the-nexus-iq-server-image)
* [Testing the Dockerfile](#testing-the-dockerfile)
* [Persistent Data](#persistent-data)
* [License](#license)

## Running

To run with ports 8070 (web UI) and 8071 (admin port) use:

    docker run -d -p 8070:8070 -p 8071:8071 --name nexus-iq-server sonatype/nexus-iq-server

or to let docker assign available ports use:

    docker run -d -p 8070 -p 8071 --name nexus-iq-server sonatype/nexus-iq-server

To get the assigned port or check if the server is running use:

    docker ps --filter "name=nexus-iq-server"

## Building the Nexus IQ Server image

To build a docker image from the Dockerfile you can use this command:

    docker build --rm=true --tag=sonatype/nexus-iq-server .

The following optional variables can be used when building the image:

- IQ_SERVER_VERSION: Version of Nexus IQ Server
- IQ_SERVER_SHA256: Check hash matches the downloaded IQ Server archive or else fail build. Required if `IQ_SERVER_VERSION` is provided.
- JAVA_URL: Download URL for Oracle JDK
- JAVA_SHA256: Check hash matches the downloaded JDK or else fail build. Required if `JAVA_URL` is provided.
- SONATYPE_WORK: Path to Nexus IQ Server working directory where variable data is stored

## Chef Solo for Runtime and Application

Chef Solo is used to build out the runtime and application layers of the Docker image. The Chef cookbook being used is available
on GitHub at [sonatype/chef-nexus-iq-server](https://github.com/sonatype/chef-nexus-iq-server).

## Testing the Dockerfile

We are using `rspec` as test framework. `serverspec` provides a docker backend (see the method `set` in the test code)
 to run the tests inside the docker container, and abstracts away the difference between distributions in the tests
 (e.g. yum, apt,...).

    rspec [--backtrace] spec/Dockerfile_spec.rb

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

## Configuration

The `solo.json.erb` template file can be used to customize the Nexus IQ Server configuration. Any attribute values added
under `nexus_iq_server:config` will become config.yml and it supports everything that the Nexus IQ Server supports. See
[IQ Server Configuration](https://help.sonatype.com/display/NXIQ/IQ+Server+Configuration) for more details.

Here is an example of the nexus_iq_server configuration section of the `solo.json.erb` template with default values from
the [sonatype/chef-nexus-iq-server](https://github.com/sonatype/chef-nexus-iq-server) cookbook:

```
  :nexus_iq_server => {
    :version => '1.39.0-04',
    :checksum => '596767950fdb8b7cfa1c690dba3ce8734a728e3baf27036172cc54d8a87b5d61',
    :install_dir => '/opt/sonatype/nexus-iq-server/',
    :logs_dir => '/var/log/nexus-iq-server',
    :conf_dir => '/etc/nexus-iq-server',
    :config => {
      :sonatypeWork => '/sonatype-work',
      :http => {
        :port => 8070,
        :adminPort => 8071,
        :requestLog => {
          :console => {
            :enabled => true
          },
          :file => {
            :currentLogFilename => '/var/log/nexus-iq-server/request.log',
            :archivedLogFilenamePattern => "/var/log/nexus-iq-server/request-\%d.log.gz",
            :archivedFileCount => 50
          }
        }
      },
      :logging => {
        :level => 'DEBUG',
        :loggers => {
          :'com.sonatype.insight.scan' => 'INFO',
          :'eu.medsea.mimeutil.MimeUtil2' => 'INFO',
          :'org.apache.http' => 'INFO',
          :'org.apache.http.wire' => 'ERROR',
          :'org.eclipse.birt.report.engine.layout.pdf.font.FontConfigReader' => 'WARN',
          :'org.eclipse.jetty' => 'INFO',
          :'org.apache.shiro.web.filter.authc.BasicHttpAuthenticationFilter' => 'INFO'
        },
        :console => {
          :enabled => true,
          :threshold => 'INFO',
          :logFormat => "\%d{'yyyy-MM-dd HH:mm:ss,SSSZ'} \%level [\%thread] \%X{username} \%logger \%msg\%n"
        },
        :file => {
          :enabled => true,
          :threshold => 'INFO',
          :currentLogFilename => '/var/log/nexus-iq-server/clm-server.log',
          :archivedLogFilenamePattern => "/var/log/nexus-iq-server/clm-server-\%d.log.gz",
          :archivedFileCount => 50,
          :logFormat => "\%d{'yyyy-MM-dd HH:mm:ss,SSSZ'} \%level [\%thread] \%X{username} \%logger \%msg\%n"
        }
      }
    }
  }
```

## License

Unless noted in their header, files in this GitHub repository are licensed under the [Apache v2 license](LICENSE)

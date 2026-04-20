/*
 * Copyright (c) 2017-present Sonatype, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>

#define MAX_ARGS 128

/*
 * This launcher exists because the distroless runtime image has no shell.
 * It replaces the previous shell-based start.sh and handles:
 *   1. Redirecting stderr to /var/log/nexus-iq-server/stderr.log
 *   2. Parsing and injecting JAVA_OPTS environment variable
 *
 * Uses execvp() to replace itself with the JVM, preserving PID for signal handling.
 * Note that Java itself has no equivalent of execvp, which is why this is written in C.
 */
int main(void) {
    char *args[MAX_ARGS];
    int arg_count = 0;

    // Redirect stderr to log file
    int stderr_fd = open("/var/log/nexus-iq-server/stderr.log",
                         O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (stderr_fd >= 0) {
        dup2(stderr_fd, STDERR_FILENO);
        close(stderr_fd);
    }

    // Build argument list
    args[arg_count++] = "java";
    args[arg_count++] = "@/opt/sonatype/nexus-iq-server/jvm.options";

    // Parse JAVA_OPTS - simple whitespace splitting (matches unquoted $JAVA_OPTS in bash)
    char *opts_copy = NULL;
    char *java_opts = getenv("JAVA_OPTS");
    if (java_opts != NULL && java_opts[0] != '\0') {
        opts_copy = strdup(java_opts);
        if (opts_copy == NULL) {
            fprintf(stderr, "Warning: failed to allocate memory for JAVA_OPTS, ignoring: %s\n", java_opts);
        } else {
            char *token = strtok(opts_copy, " \t\n");
            while (token != NULL && arg_count < MAX_ARGS - 5) {
                args[arg_count++] = token;
                token = strtok(NULL, " \t\n");
            }
        }
    }

    // Add remaining arguments
    args[arg_count++] = "-jar";
    args[arg_count++] = "/opt/sonatype/nexus-iq-server/nexus-iq-server.jar";
    args[arg_count++] = "server";
    args[arg_count++] = "/etc/nexus-iq-server/config.yml";
    args[arg_count] = NULL;

    // Exec - replace this process with java
    execvp("java", args);

    // If we get here, exec failed
    perror("execvp failed");
    free(opts_copy);
    return 1;
}

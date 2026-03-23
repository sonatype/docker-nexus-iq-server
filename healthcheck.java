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

import java.net.HttpURLConnection;
import java.net.URI;

class healthcheck {
    public static void main(String[] args) throws Exception {
        HttpURLConnection conn = (HttpURLConnection)
            URI.create("http://localhost:8071/healthcheck").toURL().openConnection();
        conn.setConnectTimeout(5000);
        conn.setReadTimeout(5000);
        System.exit(conn.getResponseCode() == 200 ? 0 : 1);
    }
}

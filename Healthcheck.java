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

import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URI;

public class Healthcheck {
  public static void main(String[] args) throws Exception {
    boolean appMode = "--app".equals(args.length > 0 ? args[0] : null);
    String url = appMode
        ? "http://localhost:8070/"
        : "http://localhost:8071/healthcheck";
    long deadline = System.currentTimeMillis() + 120_000;
    while (true) {
      try {
        HttpURLConnection conn = (HttpURLConnection)
            URI.create(url).toURL().openConnection();
        conn.setConnectTimeout(5000);
        conn.setReadTimeout(5000);
        conn.setInstanceFollowRedirects(true);
        int code = conn.getResponseCode();
        if (appMode) {
          InputStream in = code < 400 ? conn.getInputStream() : conn.getErrorStream();
          if (in != null) {
            System.out.write(in.readAllBytes());
            in.close();
          }
        }
        System.exit(code == 200 ? 0 : 1);
      } catch (Exception e) {
        if (System.currentTimeMillis() >= deadline) {
          throw e;
        }
        Thread.sleep(2000);
      }
    }
  }
}

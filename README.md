Foil
====

Foil is a fast, simple WebDAV proxy written in Ruby. Foil can adapt other structures (file systems, remote HTTP servers, database models, etc.) into WebDAV resources.

Requirements
------------

* Ruby >= 1.9.2

Running
-------

* Create a configuration file. The configuration uses the YAML format:

    host: 0.0.0.0
    port: 3000
    handler: thin
    pid_path: /var/run/foil.pid
    log_path: /var/run/foil.log
    repositories:
      myserver:
        domain: example\.com
        authentication_url: https://example.com/auth
        authentication_url: https://example.com/notify
        mounts:
          /:
            type: local
            local:
              root: /var/www/example
            headers:
              'Access-Control-Allow-Origin': '*'
          /public:
            type: s3
            local:
              root: /
              bucket: mybucket
              aws_access_key_id: mykey
              aws_secret_access_key: mysecret

* Then start the server with:

    sudo bin/foil -c config.yml start

License
-------

This software is licensed under the MIT License.

Copyright © 2011 Alexander Staubo

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

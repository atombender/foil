Foil
====

Foil is a fast, simple WebDAV proxy written in Ruby, and based on the Rack interface. Foil can adapt any kind of structure (file systems, remote HTTP servers, database models, etc.) into WebDAV resources.

Requirements
------------

* Ruby >= 1.9.2
* Thin (for running standalone)

Running
-------

Create a configuration file. The configuration uses the YAML format:

    host: 0.0.0.0
    port: 3000
    pid_path: /var/run/foil.pid
    log_path: /var/run/foil.log
    repositories:
      myserver:
        domain: example\.com
        authentication_url: https://example.com/auth
        notification_url: https://example.com/notify
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

To run a standalone server:

    sudo bin/foil -c config.yml start

Otherwise, simply mount `Foil::Handler` in your Rack application and configure it:

    Foil::Application.new.configure!({:repositories => ...})

Configuration
-------------

Foil routes WebDAV access into a simply layered system of repositories, mounts and adapters:

* Repositories are like virtual hosts: they are associated with a domain or some other pattern that lets Foil know which repository to use based on an incoming requests.
* Mounts simply maps one URI space to an adapter.
* Adapters handle the actual resources. A filesystem adapter is provided, but it's simple to write new ones that work with non-file objects.

Regexp groups from the repository rules can be used later. Here is a repository that maps to a root inferred from the URL:

    repositories:
      myserver:
        domain: ^(?<domain>[^\.]+)\.example\.com
        mounts:
          /:
            type: local
            local:
              root: /var/www/example/{{domain}}

License
-------

This software is licensed under the MIT License.

Copyright © 2011 Alexander Staubo

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

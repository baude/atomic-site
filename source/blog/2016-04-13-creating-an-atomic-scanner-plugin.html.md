---
title: Creating an atomic scanner plugin
author: baude
date: 2016-04-13 19:51:37 UTC
published: false
comments: true
---

The initial design of the scan function in the [atomic](https://github.com/projectatomic/atomic) application was to allow users to check their images and containers for vulnerabilities.  The original design used the [openscap](https://www.open-scap.org/) project within very privileged container which communicated with the atomic over a DBUS connection.  While that architecture was viable and functional, we have recently rewrote the scan function within atomic to improve realibility, decrease the required privileges, and allow for plugins to the atomic scan command.  The default scan for atomic is still a vulnerability scan and it also still uses the openscap project; however, now the openscap container has no special privileges and DBUS is no longer used for messages.  

The new architecture now allows for you to create a custom scanner in atomic.  The scanner no longer has to be sctrictly for find vulnerabilities.  For example, you could create a scanner that lists all the RPMs in the given images or containers.

The scanning function is delivered in an image that will be run by atomic.  The image must be self-contained
and perform all of the scanning function. Before attempting to create a plug-in, you will need to understand
the input and output expectations  for atomic; that is to say, what will atomic ‘hand over’ to your scanner
and what atomic expects  your scanner to ‘hand back.’  You will also need to understand the plug-in
configuration file as well.

## Configuration Files

The configuration file for plug-ins resides in /etc/atomic.d.  Atomic ships a single plug-in
[configuration](https://raw.githubusercontent.com/projectatomic/atomic/master/atomic.d/openscap) for
scanning with the openscap project.  The plugin format is as follows:

```
type: scanner
scanner_name:
image_name: fully-qualified image name
default_scan:
custom_args: [optional]
scans: [
      { name: scan1,
        args: [...],
        description: "Performs scan1"},
      { name: scan2,
        args: [...],
        description: "Performs scan2"
      }
]
```
The scanner arguments must be in list format.  You must also define one of your of your scans as
the default scan for your scanner plugin.  You can also add an optional key and value for _custom_args_ which
allows you to add custom arguments to the docker command.  This is typically used for bind mounting additonal
directories on the host filesystem for your scanning application. And finally, the image name must be
fully-qualified because this is used to pull the image if it is not already local.

## Installing your configuration file

The preferred way to install your plugin’s configuration file is through the use of the atomic’s
install command.  This command will execute the INSTALL label on the image. Typically, the INSTALL label is
a combination of a temporary docker container command and a script to be executed by the container.  An
example INSTALL label might look like this:

```
LABEL INSTALL ‘docker run -it --rm -v /etc/atomic.d:/host/etc/atomic.d ${IMAGE} install.sh’
```

And the corresponding _install.sh_ could be as simple as:

```
#/bin/sh
echo “Installing configuration file for PLUGIN_NAME”
cp -v /PLUGIN_NAME /host/etc/atomic.d
```
The destination of the configuration file in the install script is preceeded by _/host_ because
that is where the host's _/etc/atomic.d/_ is bind mounted into the container as described by
the INSTALL label above.

## Input from atomic

As of now, atomic scan can take four different inputs for which containers or images to scan. They are:

* --images (scan all images)
* --containers (scan all containers)
* --all (scan all containers and images)
* a list of images or containers (provide a list of image or container names or IDs.

Atomic will then mount the filesystem of each container or image to a time stamped directory under
_/run/atomic/time-stamp_.  Each container or image will be mounted to a directory with its ID.  So for example,
if you were scanning two images that had IDs of cef54 and b36fg respectively, the directory structure would
look like:

```
/run/atomic/time-stamp
     cef54.../
     b36fg.../
```

When atomic runs your scanning image, it will always mount _/run/atomic/time-stamp_ to your container's
_/scanin_ directory.  Your scanning container simply needs to walk the first level of directories under
_/scanin_ for processing. And because the directories are named with the ID of the object, you have a
nice key to organize your output data.

## Output to atomic

Just like how atomic will bind mount the chroots to _/scanin_, it also bind mounts a _/scanout_ directory
to the container.  On the host, the _/scanout_ directory is actually mapped to
_/var/lib/atomic/scanner-name/time-stamp_.  Atomic expects you to put your output in the _/scanout_ directory,
again organizing your output data by directory names that correlate to the IDs of the object.  You can output
whatever data files you want but you must output a json file in each directory that follows the required template so
that atomic can display some information to stdout for the user.

An example of what this directory structure looks like on the host can be as follows:

```
/var/lib/atomic/scanner-name/time-stamp/
   cef54../
        json
    b36fb../
        json
```

## JSON template

The required JSON template must be formed as follows:

```
{
  "Time": "timestamp",
  "Finished Time": "timestamp",
  "Successful": "true",
  "Scan Type": "Description of scan",
  "UUID": "/scanin/ID_of_object",
  "CVE Feed Last Updated": "timestamp",
  "Scanner": "scanner_name",
  "Vulnerabilities": [
    {
      "Custom": {
        "custom_key1": "custom_val1",
        "custom_key2": [
          {
            "custom_key3": "custom_val3",
            "custom_key_4": "custom_val4"
            ...
```
If the type of scanning you are performing is not related to CVEs or identifying vulnerabilities, you
can change the _Vulnerabilities_ key results _Results_. Notice that you can use the _custom_ tag to
add custom outputs.  Atomic will recursively follow the _custom_ tag and will output the key and values
verbatim as they are.


## A sample custom scanner

If you want to create a custom scanner plugin for Atomic, you need to have prepared the following elements:

* A configuration file that describes your scanner plug-in
* An install script that prepares the host to run your scanning application
* Your scanning application
* An image that contains all of the above.

In my example below, I have created a custom scan plug-in that allows you to list all the RPMs in an image, which
is the default scan type for my image.  I also provide an alternative scan type that allows you to list the OS
version of each image.

### Configuration file

This configuration file is what enables your scanner plug-in with Atomic.  Note that you can provide
one or more types of scans in your configuration file but you must set a default.  In the case of my
custom configuration file, there are two scan types defined: rpm-list and get-os.  Notice how they each
call the python executable with a different argument which allows me to differentiate between the two.

```
type: scanner
scanner_name: example_plugin
image_name: example_plugin
default_scan: rpm-list
custom_args: ['-v', '/tmp/foobar:/foobar']
scans: [
      { name: rpm-list,
        args: ['python', 'list_rpms.py', 'list-rpms'],
        description: "List all RPMS",
      },
      { name: get-os,
        args: ['python', 'list_rpms.py', 'get-os'],
        description: "Get the OS of the object",
      }
]

```
### Install script

The install script is used by the _atomic install_ command to put your scanner's configuration file in the
correct directory on the host filesystem.  The _atomic install_ command uses the INSTALL label in your
image to call the install script you have provided.  The following is a simple install script that copies
my example_plugin configuration file to /etc/atomic.d on the host filesystem using the bind mount defined
in the INSTALL label (shown in the Dockerfile below).

```
#/bin/bash

echo "Copying example_plugin configuration file to host filesystem..."

cp -v /example_plugin /host/etc/atomic.d/
```

### Executable

Obviously a scanner can be very complex.  My example scanner here is a relatively simple python executable that
can list the RPMs in an image or show its OS version.  Note how in the python executable, the results are
written to json files in the required template.

```
import os
import subprocess
from datetime import datetime
import json
from sys import argv

class ScanForInfo(object):
    INDIR = '/scanin'
    OUTDIR = '/scanout'

    def __init__(self):
        self._dirs = [ _dir for _dir in os.listdir(self.INDIR) if os.path.isdir(os.path.join(self.INDIR, _dir))]

    def list_rpms(self):
        for _dir in self._dirs:
            full_indir = os.path.join(self.INDIR, _dir)
            # If the chroot has the rpm command
            if os.path.exists(os.path.join(full_indir, 'usr/bin/rpm')):
                full_outdir = os.path.join(self.OUTDIR, _dir)

                # Get the RPMs
                cmd = ['rpm', '--root', full_indir, '-qa']
                rpms = subprocess.check_output(cmd).split()

                # Construct the JSON
                rpms_out = {'Custom': {}}
                rpms_out['Custom']['rpms'] = rpms

                # Make the outdir
                os.makedirs(full_outdir)

                # Writing JSON data
                self.write_json_to_file(full_outdir, rpms_out, _dir)

    def get_os(self):
        for _dir in self._dirs:
            full_indir = os.path.join(self.INDIR, _dir)
            os_release = None
            for location in ['etc/release', 'etc/redhat-release','etc/debian_version']:
                try:
                    os_release = open(os.path.join(full_indir, location), 'r').read()
                except IOError:
                    pass
                if os_release is not None:
                    break

            full_outdir = os.path.join(self.OUTDIR, _dir)

            # Construct the JSON
            out = {'Custom': {}}
            out['Custom']['os_release'] = os_release

            # Make the outdir
            os.makedirs(full_outdir)

            # Writing JSON data
            self.write_json_to_file(full_outdir, out, _dir)

    @staticmethod
    def write_json_to_file(outdir, json_data, uuid):
        current_time = datetime.now().strftime('%Y-%m-%d-%H-%M-%S-%f')
        json_out = {
            "Time": current_time,
            "Finished Time": current_time,
            "Successful": "true",
            "Scan Type": "List RPMs",
            "UUID": "/scanin/{}".format(uuid),
            "CVE Feed Last Updated": "NA",
            "Scanner": "example_plugin",
            "Results": [json_data],
        }
        with open(os.path.join(outdir, 'json'), 'w') as f:
             json.dump(json_out, f)


scan = ScanForInfo()
if argv[1] == 'list-rpms':
    scan.list_rpms()
elif argv[1] == 'get-os':
    scan.get_os()
```

### Dockerfile

The Dockerfile for my example plug-in is very simple.  It contains an INSTALL label so that _atomic install_ will
function properly.  And besides the CentOS base image, it simply adds the example plugin configuration file, the
scanner executable, and the install.sh script itself.

```
from centos:latest

LABEL INSTALL='docker run -it --rm -v /etc/atomic.d/:/host/etc/atomic.d/ $IMAGE sh /install.sh'

ADD example_plugin /
ADD list_rpms.py /
ADD install.sh /
```

### The user experience

As is the mission of the atomic application, the user experience for using the new scanner image
is very crisp and easy.  The first step in using the image is to use _atomic install_ to prepare the
host operating system.  In the case of this example, we simply need to 'expose' the example_plugin
configuration file from the image to /etc/atomic.d/ on the host.

```
# sudo atomic install example_plugin
docker run -it --rm -v /etc/atomic.d/:/host/etc/atomic.d/ example_plugin sh /install.sh
Copying example_plugin configuration file to host filesystem...
'/example_plugin' -> '/host/etc/atomic.d/example_plugin'
#
```

With _atomic install_, if the image is not local, atomic will pull the image from the correct repository
onto your host.  In the example case, the image was already local.  Now the host is aware of the new plugin and
we can verify what scanning options are available to us with the _atomic scan_ command.

```
# sudo atomic scan --list
Scanner: openscap *
  Image Name: openscap
     Scan type: cve_scan *
     Description: Performs a CVE scan based on known CVE data

     Scan type: standards_scan
     Description: Performs a standard scan

Scanner: example_plugin
  Image Name: example_plugin
     Scan type: rpm-list *
     Description: List all RPMS

     Scan type: get-os
     Description: Get the OS of the object


* denotes default
```

When viewing the list of available scan options, notice how asterisks (*) are use to denote defaults.  In this case,
you can see that 'openscap' is the default scanner and its 'cve_scan' is the default scan type.  For our example
plugin, 'rpm-list' is the default scan type and 'get-os' is an additional scan type.  You can set the default
scanner in the /etc/atomic configuration file.

You can use the '--scanner' option in _atomic scan_ to switch scanners and if no ''--scan_type' is provided,
it will use the default scan type declared for that scanner.

```
# sudo atomic scan --scanner example_plugin centos
docker run -it --rm -v /etc/localtime:/etc/localtime -v /run/atomic/2016-04-12-08-08-15-631629:/scanin -v /var/lib/atomic/example_plugin/2016-04-12-08-08-15-631629:/scanout -v /tmp/foobar:/foobar example_plugin python list_rpms.py list-rpms

centos (28e524afdd052cf)

The following results were found:

       rpms:
         centos-release-7-2.1511.el7.centos.2.10.x86_64
         filesystem-3.2-20.el7.x86_64
         basesystem-10.0-7.el7.centos.noarch
         nss-softokn-freebl-3.16.2.3-13.el7_1.x86_64
         glibc-2.17-106.el7_2.4.x86_64
         ...
         rpm-python-4.11.3-17.el7.x86_64
         pyliblzma-0.5.3-11.el7.x86_64
         yum-plugin-fastestmirror-1.1.31-34.el7.noarch
         python-chardet-2.2.1-1.el7_1.noarch
         yum-utils-1.1.31-34.el7.noarch
         vim-minimal-7.4.160-1.el7.x86_64


Files associated with this scan are in /var/lib/atomic/example_plugin/2016-04-12-08-08-15-631629.

```
Notice how atomic scan will also cite where the output files from the scan are located.

If you wanted to use the example_plugin scanner and the scan_type of 'get-os', you simply need to pass both
the '--scanner' and '--scan_type' command switches.

```
# sudo atomic scan --scanner example_plugin --scan_type get-os centos ubuntu
docker run -it --rm -v /etc/localtime:/etc/localtime -v /run/atomic/2016-04-12-08-09-00-506401:/scanin -v /var/lib/atomic/example_plugin/2016-04-12-08-09-00-506401:/scanout -v /tmp/foobar:/foobar example_plugin python list_rpms.py get-os

ubuntu (c9ea60d0b9055c2)

The following results were found:

       os_release: jessie/sid



centos (28e524afdd052cf)

The following results were found:

       os_release: CentOS Linux release 7.2.1511 (Core)



Files associated with this scan are in /var/lib/atomic/example_plugin/2016-04-12-08-09-00-506401.
```
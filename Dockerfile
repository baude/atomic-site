FROM mattdm/fedora
MAINTAINER mscherer@redhat.com
WORKDIR /tmp
RUN yum upgrade -y 
RUN yum install -y rubygem-bundler ruby-devel git make gcc gcc-c++
ADD config.rb /tmp/config.rb
ADD data /tmp/data
ADD Gemfile  /tmp/Gemfile
ADD Gemfile.lock /tmp/Gemfile.lock
ADD lib /tmp/lib
ADD source /tmp/source
 
RUN bundle install 
EXPOSE 4567
CMD bundle exec middleman server


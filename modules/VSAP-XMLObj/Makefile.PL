use 5.006001;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'VSAP::XMLObj',
    VERSION_FROM      => 'lib/VSAP/XMLObj.pm', # finds $VERSION
    PREREQ_PM         => { XML::SimpleObject::LibXML => 0 }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/VSAP/XMLObj.pm', # retrieve abstract from module
       AUTHOR         => 'System Administrator <root@iserver.com>') : ()),
);

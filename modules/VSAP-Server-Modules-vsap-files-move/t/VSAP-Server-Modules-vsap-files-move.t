# t/VSAP-Server-Modules-vsap-files-move.t

use Test::More tests => 45;

use strict;

#-----------------------------------------------------------------------------
#
# startup
#

BEGIN {
  use_ok('VSAP::Server::Modules::vsap::files');
  use_ok('VSAP::Server::Modules::vsap::files::move');
  use_ok('VSAP::Server::Modules::vsap::config');
  use_ok('VSAP::Server::Test::Account');
};

#-----------------------------------------------------------------------------
#
# set up a dummy server admin 'quuxroot'
#
my $acctquuxroot = VSAP::Server::Test::Account->create( { username => 'quuxroot',
                                                          password => 'quuxrootbar',
                                                          fullname => 'Quux Root',
                                                          shell => '/sbin/noshell' } );
ok(getpwnam('quuxroot'), 'successfully created new user');

rename("/usr/local/etc/cpx.conf", "/usr/local/etc/cpx.conf.$$")
    if (-e "/usr/local/etc/cpx.conf");
open(SOURCE, "/www/conf/httpd.conf") || die "Could not open httpd.conf";
open(BACKUP, ">/www/conf/httpd.conf.$$") || die "Could not create backup of httpd.conf";
print BACKUP $_ while (<SOURCE>);
close(BACKUP);
close(SOURCE);
rename("/etc/mail/virtusertable", "/etc/mail/virtusertable.$$")
    if (-e "/etc/mail/virtusertable");

#-----------------------------------------------------------------------------
#
# create a new vsap test object
#
my $vsap = $acctquuxroot->create_vsap( ["vsap::auth", "vsap::user",
                                        "vsap::files::move"] );
my $t = $vsap->client({ username => 'quuxroot', password => 'quuxrootbar'});
ok(ref($t), "create new VSAP test object for non-privileged user");

#-----------------------------------------------------------------------------
#
# some simple error checks
#
my $filename = (getpwnam('quuxroot'))[7] . "/hello_world.txt";
my $target = (getpwnam('quuxroot'))[7] . "/move";
my $query = qq!
<vsap type="files:move">
  <source>/hello_world.txt</source>
  <target></target>
</vsap>
!;
my $de = $t->xml_response($query);
my $value = $de->findvalue("/vsap/vsap[\@type='error']/code");
is($value, 106, "error check: target undefined");

$query = qq!
<vsap type="files:move">
  <source></source>
  <target>/move</target>
</vsap>
!;
undef($de);
$de = $t->xml_response($query);
$value = $de->findvalue("/vsap/vsap[\@type='error']/code");
is($value, 101, "error check: path undefined");

$query = qq!
<vsap type="files:move">
  <source>/hello_world.txt</source>
  <target>/move</target>
</vsap>
!;
undef($de);
$de = $t->xml_response($query);
$value = $de->findvalue("/vsap/vsap[\@type='error']/code");
is($value, 102, "error check: -e path");

#-----------------------------------------------------------------------------
#
# check move capability (and restrictions) of non-privileged user
#
open(TEMP, ">$filename");
print TEMP "hello world!\n";
close(TEMP);
my ($uid, $gid) = (getpwnam('quuxroot'))[2,3];
chown($uid, $gid, $filename);
ok((-e "$filename"), "created temp file in userdir to be moved");
$query = qq!
<vsap type="files:move">
  <source>/hello_world.txt</source>
  <target>/move</target>
</vsap>
!;
undef($de);
$de = $t->xml_response($query);
$value = $de->findvalue("/vsap/vsap[\@type='files:move']/success/path/target");
is($value, "/move/hello_world.txt", "move self-owned file to subdirectory: VSAP returned ok");
ok((-e "$target/hello_world.txt"), "verify move was successful; file exists");
my ($tuid, $tgid) = (lstat("$target/hello_world.txt"))[4,5];
is($tuid, (getpwnam('quuxroot'))[2], "verify correct ownership of moved file");
unlink("$target/hello_world.txt");
unlink($filename);

$filename = "/biff/../../tmp/hello_world.txt";
$query = qq!
<vsap type="files:move">
  <source>$filename</source>
  <target>$target</target>
</vsap>
!;
undef($de);
$de = $t->xml_response($query);
$value = $de->findvalue("/vsap/vsap[\@type='error']/code");
is($value, 100, "VSAP does not authorize non-privileged user to move non-homed files");
ok(!(-e "$target/hello_world.txt"), "non-privileged user cannot move files outside of homedir");

#-----------------------------------------------------------------------------
#
# check move capability of server admin on root-owned files
#
$acctquuxroot->make_sa();
undef($t);
$t = $vsap->client({ username => 'quuxroot', password => 'quuxrootbar'});
ok(ref($t), "create new VSAP test object for server admin");
$filename = "/tmp/hello_world.txt";
open(TEMP, ">$filename");
print TEMP "hello world!\n";
close(TEMP);
ok((-e "$filename"), "created temp file in tmp to be moved");
$query = qq!
<vsap type="files:move">
  <source>$filename</source>
  <target>$target</target>
</vsap>
!;
undef($de);
$de = $t->xml_response($query);
$value = $de->findvalue("/vsap/vsap[\@type='files:move']/success/path/target");
is($value, "$target/hello_world.txt", "move root-owned file by server admin: VSAP returned ok");
ok((-e "$target/hello_world.txt"), "verify move was successful; file exists");
($tuid, $tgid) = (lstat("$target/hello_world.txt"))[4,5];
is($tuid, (getpwnam('quuxroot'))[2], "verify correct ownership of moved file");
unlink("$target/hello_world.txt");
unlink($filename);
# move from root-owned space to root-owned space
$target = "/tmp/move";
open(TEMP, ">$filename"); 
print TEMP "hello world!\n";
close(TEMP);
ok((-e "$filename"), "created temp file in tmp to be moved");
$query = qq!
<vsap type="files:move">
  <source>$filename</source>
  <target>$target</target>
</vsap>
!;
undef($de); 
$de = $t->xml_response($query);
$value = $de->findvalue("/vsap/vsap[\@type='files:move']/success/path/target");
is($value, "$target/hello_world.txt", "move root-owned file by server admin to root-owned dir: VSAP returned ok");
ok((-e "$target/hello_world.txt"), "verify move was successful; file exists");
($tuid, $tgid) = (lstat("$target/hello_world.txt"))[4,5];
is($tuid, (getpwnam('root'))[2], "verify correct ownership of moved file"); 
unlink("$target/hello_world.txt");
rmdir($target);
unlink($filename);


#-----------------------------------------------------------------------------
#
# add a new domain admin user
#
my $addquery = qq!
<vsap type="user:add">
  <login_id>quuxfoo</login_id>
  <fullname>Quux Foo</fullname>
  <password>quuxf00bar</password>
  <confirm_password>quuxf00bar</confirm_password>
  <quota>19</quota>
  <da>
    <domain>quuxfoo.com</domain>
    <ftp_privs/>
    <mail_privs/>
    <shell_privs/>
    <shell>/bin/tcsh</shell>
    <eu_capa_ftp/>
    <eu_capa_mail/>
    <eu_capa_shell/>
  </da>
</vsap>
!;

undef($de);
$de = $t->xml_response($addquery);
$value = $de->findvalue("/vsap/vsap[\@type='user:add']/status");
is($value, "ok", 'user:add returned success for domain admin (quuxfoo)');

# add a vhost to the httpd.conf file and monkey with the cpx config
open(CONF, ">>/www/conf/httpd.conf");
print CONF <<'ENDVHOST';
<VirtualHost quuxfoo.com>
  User quuxfoo
  ServerName quuxfoo.com
  ServerAlias www.quuxfoo.com
  ServerAdmin quuxfoo@quuxfoo.com
  DocumentRoot /home/quuxfoo
</virtualHost>
ENDVHOST
close(CONF);

# assign domain to domain admin
my $co = new VSAP::Server::Modules::vsap::config( username => 'quuxfoo');
$co->add_domain('quuxfoo.com');
$co->domain('quuxfoo.com');
$co->user_limit('quuxfoo.com', 3);
$co->commit;
undef($co);

#-----------------------------------------------------------------------------
#
# check move capability of server admin on user-owned files
#
$filename = (getpwnam('quuxfoo'))[7] . "/hello_world.txt";
$target = (getpwnam('quuxroot'))[7] . "/move";
open(TEMP, ">$filename");
print TEMP "hello world!\n";
close(TEMP);
($uid, $gid) = (getpwnam('quuxfoo'))[2,3];
chown($uid, $gid, $filename);
ok((-e "$filename"), "created temp file in quuxfoo userdir");
$query = qq!
<vsap type="files:move">
  <source>$filename</source>
  <target>$target</target>
</vsap>
!;
undef($de);
$de = $t->xml_response($query);
$value = $de->findvalue("/vsap/vsap[\@type='files:move']/success/path/target");
is($value, "$target/hello_world.txt", "move user-owned file by server admin: VSAP returned ok");
ok((-e "$target/hello_world.txt"), "verify move was successful; file exists");
($tuid, $tgid) = (lstat("$target/hello_world.txt"))[4,5];
is($tuid, (getpwnam('quuxroot'))[2], "verify correct ownership of moved file");
unlink("$target/hello_world.txt");
unlink($filename);

#-----------------------------------------------------------------------------
#
# add an end user to domain admin
#
undef $t;
$t = $vsap->client( { password => 'quuxf00bar', username => 'quuxfoo'});
ok(ref($t), "create new VSAP test object for domain admin (quuxfoo)");

$query = qq!
<vsap type="user:add">
  <login_id>quuxfoochild1</login_id>
  <fullname>Quux Foo Child 1</fullname>
  <password>quuxf00childbar1</password>
  <confirm_password>quuxf00childbar1</confirm_password>
  <quota>10</quota>
  <eu>
    <domain>quuxfoo.com</domain>
    <mail_privs/>
    <shell_privs/>
    <shell>/bin/tcsh</shell>
  </eu>
</vsap>
!;

undef $de;
$de = $t->xml_response($query);
$value = $de->findvalue("/vsap/vsap[\@type='user:add']/status");
is($value, "ok", 'vsap user:add returned ok status for enduser1');

#-----------------------------------------------------------------------------
#
# check lack of move capability of domain admin on non-enduser-owned files
#
$filename = (getpwnam('quuxroot'))[7] . "/hello_world.txt";
$target = (getpwnam('quuxfoo'))[7] . "/move";
open(TEMP, ">$filename");
print TEMP "hello world!\n";
close(TEMP);
($uid, $gid) = (getpwnam('quuxroot'))[2,3];
chown($uid, $gid, $filename);
ok((-e "$filename"), "created temp file in non-enduser homedir");
$query = qq!
<vsap type="files:move">
  <source>$filename</source>
  <source_user>quuxroot</source_user>
  <target>$target</target>
</vsap>
!;
undef($de);
$de = $t->xml_response($query);
$value = $de->findvalue("/vsap/vsap[\@type='error']/code");
is($value, 105, "VSAP does not authorize domain admin to move non-enduser-owned files");
ok(!(-e "$target/hellow_world.txt"), "domain admin unable to move non-enduser-owned files");
unlink($filename);

#-----------------------------------------------------------------------------
#
# check move capability of domain admin on enduser-owned files
#
$filename = (getpwnam('quuxfoochild1'))[7] . "/hello_world.txt";
open(TEMP, ">$filename");
print TEMP "hello world!\n";
close(TEMP);
($uid, $gid) = (getpwnam('quuxfoochild1'))[2,3];
chown($uid, $gid, $filename);
ok((-e "$filename"), "created temp file in enduser homedir");
$query = qq!
<vsap type="files:move">
  <source>/hello_world.txt</source>
  <source_user>quuxfoochild1</source_user>
  <target>/move</target>
</vsap>
!;
undef($de);
$de = $t->xml_response($query);
$value = $de->findvalue("/vsap/vsap[\@type='files:move']/success/path/target");
is($value, "/move/hello_world.txt", "move enduser-owned file by domain admin: VSAP returned ok");
ok((-e "$target/hello_world.txt"), "verify move was successful; file exists");
($tuid, $tgid) = (lstat("$target/hello_world.txt"))[4,5];
is($tuid, (getpwnam('quuxfoo'))[2], "verify correct ownership of moved file");
unlink("$target/hello_world.txt");
unlink($filename);

#-----------------------------------------------------------------------------
#
# add another end user to domain admin
#
undef $t;
$t = $vsap->client( { password => 'quuxf00bar', username => 'quuxfoo'});

ok(ref($t), "create new VSAP test object for domain admin (quuxfoo)");

$query = qq!
<vsap type="user:add">
  <login_id>quuxfoochild2</login_id>
  <fullname>Quux Foo Child 2</fullname>
  <password>quuxf00childbar2</password>
  <confirm_password>quuxf00childbar2</confirm_password>
  <quota>7</quota>
  <eu>
    <domain>quuxfoo.com</domain>
    <mail_privs/>
    <shell_privs/>
    <shell>/bin/tcsh</shell>
  </eu>
</vsap>
!;

undef $de;
$de = $t->xml_response($query);
$value = $de->findvalue("/vsap/vsap[\@type='user:add']/status");
is($value, "ok", 'vsap user:add returned ok status for enduser2');

#-----------------------------------------------------------------------------
#
# check domain admin capability to move enduser files to another enduser dir
#
$filename = (getpwnam('quuxfoochild1'))[7] . "/hello_world.txt";
$target = (getpwnam('quuxfoochild2'))[7] . "/move";
open(TEMP, ">$filename");
print TEMP "hello world!\n";
close(TEMP);
($uid, $gid) = (getpwnam('quuxfoochild1'))[2,3];
chown($uid, $gid, $filename);
ok((-e "$filename"), "created temp file in enduser homedir");
$query = qq!
<vsap type="files:move">
  <source>/hello_world.txt</source>
  <source_user>quuxfoochild1</source_user>
  <target>/move</target>
  <target_user>quuxfoochild2</target_user>
</vsap>
!;
undef($de);
$de = $t->xml_response($query);
$value = $de->findvalue("/vsap/vsap[\@type='files:move']/success/path/target");
is($value, "/move/hello_world.txt", "move enduser-owned file by domain admin: VSAP returned ok");
ok((-e "$target/hello_world.txt"), "verify move was successful; file exists");
($tuid, $tgid) = (lstat("$target/hello_world.txt"))[4,5];
is($tuid, (getpwnam('quuxfoochild2'))[2], "verify correct ownership of moved file");
unlink("$target/hello_world.txt");
unlink($filename);

#-----------------------------------------------------------------------------
#
# cleanup
#

END {
    $acctquuxroot->delete();
    ok( ! $acctquuxroot->exists, 'Quux Root was removed.');
    getpwnam('quuxfoo') && system q(vrmuser -y quuxfoo 2>/dev/null);
    getpwnam('quuxfoochild1') && system q(vrmuser -y quuxfoochild1 2>/dev/null);
    getpwnam('quuxfoochild2') && system q(vrmuser -y quuxfoochild2 2>/dev/null);
    unlink "/usr/local/etc/cpx.conf";
    rename("/usr/local/etc/cpx.conf.$$", "/usr/local/etc/cpx.conf")
      if (-e "/usr/local/etc/cpx.conf.$$");
    rename("/www/conf/httpd.conf.$$", "/www/conf/httpd.conf")
      if (-e "/www/conf/httpd.conf.$$");
    if (-e "/etc/mail/virtusertable.$$") {
      rename("/etc/mail/virtusertable.$$", "/etc/mail/virtusertable");
      chdir("/etc/mail");
      my $out = `make`;
    }
}

# eof


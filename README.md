# Mojolicious::Plugin::SPNEGO

use Mojolicious::Lite;

```perl
my $SERVER = $ENV{AD_SERVER} // die "AD_SERVER env variable not set";

app->secrets(['My secret passphrase here']);

plugin 'SPNEGO', ad_server => $SERVER;

get '/' => sub {
   my $c = shift;
   if (not $c->session('user')){
       $c->ntlm_auth({
           auth_success_callback => sub {
               my $c = shift;
               my $user = shift;
               my $ldap = shift; # bound Net::LDAP::SPNEGO connection
               $c->session('user',$user->{samaccountname});
               $c->session('name',$user->{displayname});
               my $groups = $ldap->get_ad_groups($user->{samaccountname});
               $c->session('groups',[ sort keys %$groups]);
               return 1;
           }
       }) or return;
   }
} => 'index';

app->start;

__DATA__

@@ index.html.ep
<!DOCTYPE html>
<html>
<head>
<title>NTLM Auth Test</title>
</head>
<body>
<h1>Hello <%= session 'name' %></h1>
<div>Your account '<%= session 'user' %>' belongs to the following groups:</div>
<ul>
% for my $group (@{session 'groups' }) {
   <li>'<%= $group %>'</li>
% }
</ul>
</body>
</html>
```

# DESCRIPTION

The Mojolicious::Plugin::SPNEGO lets you provide NTLM SSO by using an
active directory server as authentication provider. The plugin uses
the [Net::LDAP::SPNEGO](https://metacpan.org/pod/Net::LDAP::SPNEGO) module.

On loading the plugin default values for the helpers can be configures:

```perl
plugin 'SPNEGO', ad_server => $SERVER;
```

The plugin provides the following helpers:

## $c->ntlm\_auth({ad\_server => $AD\_SERVER\[, auth\_success\_callback=> $cb \])

Initiate an NTLM authentication dialog with the browser by forwarding the
tokens coming from the browser to the ad server specified in the _ad\_server_
argument.

If a callback is specified it will be executed once the ntlm dialog
has completed successfully. Depending on the return value of the
callback the entire process will be considered successfull or not.

Since ntlm authentication is reather complex, you may want to save
authentication success in a cookie.

# AUTHOR

Tobias Oetiker, <tobi@oetiker.ch>

# COPYRIGHT

Copyright OETIKER+PARTNER AG 2016

# LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
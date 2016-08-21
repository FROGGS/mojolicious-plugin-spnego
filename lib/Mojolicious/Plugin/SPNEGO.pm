package Mojolicious::Plugin::SPNEGO;
use Mojo::Base 'Mojolicious::Plugin';
use Net::LDAP::SPNEGO;

our $VERSION = '0.2.1';

my %cCache;

sub register {
    my $self = shift;
    my $app = shift;
    my $plugin_cfg = ref $_[0] ? $_[0] : { @_ };
    $app->helper(
        ntlm_auth => sub {
            my $c = shift;
            my $cfg = { %$plugin_cfg, ref $_[0] ? %$_[0] :  @_ };
            my $cId = $c->tx->connection;
            my $cCache = $cCache{$cId} //= { status => 'init' };
            return if $cCache->{status} eq 'authenticated';

            my $authorization = $c->req->headers->header('Authorization') // '';
            my ($AuthBase64) = ($authorization =~ /^NTLM\s(.+)$/);
            for ($AuthBase64 and $cCache->{status} =~ /^expect(Type\d)/){
                my $ldap = $cCache->{ldapObj} //= Net::LDAP::SPNEGO->new($cfg->{ad_server},debug=>$cfg->{ldap_debug});
                /^Type1/ && do {
                    my $mesg = $ldap->bind_type1($AuthBase64);
                    if ($mesg->{ntlm_type2_base64}){
                        $c->res->headers->header( 'WWW-Authenticate' => 'NTLM '.$mesg->{ntlm_type2_base64});
                        $c->render( text => 'Waiting for Type3 NTLM Token', status => 401);
                        $cCache->{status} = 'expectType3';
                        return 0;
                    }
                    # lets try with a new connection
                    $ldap->unbind;
                    delete $cCache->{ldapObj};
                };
                /^Type3/ && do {
                    my $mesg = $ldap->bind_type3($AuthBase64);
                    if (my $user = $mesg->{ldap_user_entry}){
                        if (my $cb = $cfg->{auth_success_cb}){
                            if (not $cb or $cb->($c,$user,$ldap)){
                                $cCache->{status} = 'authenticated';
                            }
                        }
                    }
                    $ldap->unbind;
                    delete $cCache->{ldapObj};
                    return  $cCache->{status} eq 'authenticated';
                };
            }
            $c->res->headers->header( 'WWW-Authenticate' => 'NTLM' );
            $c->render( text => 'Waiting for Type 1 NTLM Token', status => 401 );
            $cCache->{status} = 'expectType1';
            return 0;
        }
    );
}

1;

__END__

=head1 Mojolicious::Plugin::SPNEGO

 use Mojolicious::Lite;

 my $SERVER = $ENV{AD_SERVER} // die "AD_SERVER env variable not set";

 app->secrets(['My secret passphrase here']);

 plugin 'SPNEGO', ad_server => $SERVER;

 get '/' => sub {
    my $c = shift;
    if (not $c->session('user')){
        $c->ntlm_auth({
            auth_success_cb => sub {
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

=head1 DESCRIPTION

The Mojolicious::Plugin::SPNEGO lets you provide NTLM SSO by using an
active directory server as authentication provider. The plugin uses
the L<Net::LDAP::SPNEGO> module.

On loading the plugin default values for the helpers can be configured:

 plugin 'SPNEGO', ad_server => $SERVER;

or

 $app->plugin('SPNEGO',ad_server => $SERVER);

The plugin provides the following helper method:

=head2 $c->ntlm_auth({ad_server => $AD_SERVER[, auth_success_cb=> $cb ])

The I<ntlm_auth> method runs an NTLM authentication dialog with the browser
by forwarding the tokens coming from the browser to the AD server specified
in the I<ad_server> argument.

If a I<auth_success_cb> is specified it will be executed once the ntlm dialog
has completed successfully. Depending on the return value of the
callback the entire process will be considered successfull or not.

Since ntlm authentication is reather complex, you may want to save
authentication success in a cookie.

Note that windows will only do automatic NTLM SSO with hosts in the local zone
so you may have to add your webserver to this group of machines in the
Internet Settings dialog.

=head1 EXAMPLE

The included example script F<eg/demo.pl> shows how to use the plugin
to implement NTLM authentication for a L<Mojolicious::Lite> web application.

Use the following steps to run the demo:

 $ perl Makefile.PL
 $ make 3rd
 $ env AD_SERVER=ad-server.example.com ./eg/demo.pl deamon

Now connect with your webbrowser to the webserver runing on port 3000. If you
login from a Windows host and the url you are connecting resides in the local
zone, you will see (or rather not see) seemless authentication taking place.
Finally a webpage will be displayed showing a list of groups you are a member of.

The demo script stores your authentication in a cookie in your brower, so once
you are authenticated, you will have to restart the browser or remove the cookie
to force another authentication.
=head1 COPYRIGHT

Copyright OETIKER+PARTNER AG 2016. All rights reserved.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

S<Tobias Oetiker, E<lt>tobi@oetiker.chE<gt>>

=head1 HISTORY

 2016-08-21 to 0.1.0 initial version

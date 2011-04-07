package Mail::Decency::Core::Exception;
use Mouse;
use Mail::Decency::MouseX::Throwable;
with 'Mail::Decency::MouseX::Throwable';

use version 0.74; our $VERSION = qv( "v0.1.4" );

=head1 NAME

Mail::Decency::Core::Exception

=head1 DESCRIPTION

Base class for exceptions in decency

=head1 SYNOPSIS

    Mail::Decency::Core::Exception::Reject->new( "some message" );

=head1 METHODS

=cut

use overload '""' => \&get_message;

has message  => ( is => "rw", isa => "Str", required => 0 );
has internal => ( is => "rw", isa => "Str", required => 0 );

sub get_message { shift->message }


package Mail::Decency::Core::Exception::Reject;
use Mouse;
extends 'Mail::Decency::Core::Exception';

package Mail::Decency::Core::Exception::Accept;
use Mouse;
extends 'Mail::Decency::Core::Exception';

package Mail::Decency::Core::Exception::Prepend;
use Mouse;
extends 'Mail::Decency::Core::Exception';

package Mail::Decency::Core::Exception::Spam;
use Mouse;
extends 'Mail::Decency::Core::Exception';

package Mail::Decency::Core::Exception::Virus;
use Mouse;
extends 'Mail::Decency::Core::Exception';

package Mail::Decency::Core::Exception::Timeout;
use Mouse;
extends 'Mail::Decency::Core::Exception';

package Mail::Decency::Core::Exception::FileToBig;
use Mouse;
extends 'Mail::Decency::Core::Exception';

package Mail::Decency::Core::Exception::Timeout;
use Mouse;
extends 'Mail::Decency::Core::Exception';

package Mail::Decency::Core::Exception::ReinjectFailure;
use Mouse;
extends 'Mail::Decency::Core::Exception';

package Mail::Decency::Core::Exception::Drop;
use Mouse;
extends 'Mail::Decency::Core::Exception';

package Mail::Decency::Core::Exception::ModuleError;
use Mouse;
extends 'Mail::Decency::Core::Exception';



=head1 AUTHOR

Ulrich Kautz <uk@fortrabbit.de>

=head1 COPYRIGHT

Copyright (c) 2011 the L</AUTHOR> as listed above

=head1 LICENCSE

This library is free software and may be distributed under the same terms as perl itself.

=cut

1;


package MouseX::MetaClassFullInherit;

use Mouse ();
use Mouse::Exporter;
use Mouse::Util::MetaRole;

Mouse::Exporter->setup_import_methods( also => 'Mouse' );

sub init_meta {
    shift;
    my %args = @_;
    Mouse->init_meta(%args);
    warn "> MY META\n";
}

1;

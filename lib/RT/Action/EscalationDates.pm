package RT::Action::EscalationDates;

use 5.010;
use strict;
use warnings;

use base qw(RT::Action);
use Date::Manip;

our $VERSION = '0.2';


=head1 NAME

C<RT::Action::EscalationDates> - Set start and due time based on escalation
settings


=head1 DESCRIPTION

This RT Action sets start and due time based on escalation settings. It provides
handling business hours defined in RT site configuration file.


=head1 INSTALLATION

This action based on the following modules:

    RT >= 4.0.0
    Date::Manip >= 6.25

It is provided by the RT Extension RT::Extension::EscalationDates so it will be
installed automatically.


=head1 CONFIGURATION

Configuration is done by RT::Extension::EscalationDates.


=head1 AUTHOR

Benjamin Heisig, E<lt>bheisig@synetics.deE<gt>


=head1 SUPPORT AND DOCUMENTATION

You can find documentation for this module with the C<perldoc> command.

    perldoc RT::Extension::EscalationDates

You can also look for information at:

=over 4

=item * Search CPAN

L<http://search.cpan.org/dist/RT-Extension-EscalationDates/>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=RT-Extension-EscalationDates>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/RT-Extension-EscalationDates>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/RT-Extension-EscalationDates>

=back


=head1 BUGS

Please report any bugs or feature requests to the L<author|/"AUTHOR">.


=head1 COPYRIGHT AND LICENSE

Copyright 2011 synetics GmbH, E<lt>http://i-doit.org/E<gt>

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

Request Tracker (RT) is Copyright Best Practical Solutions, LLC.


=head1 SEE ALSO

    RT
    Date::Manip
    RT::Extension::EscalationDates


=cut

sub Prepare {
    my $self = shift;

    my $ticket = $self->TicketObj;

    ## Check start date:
    my $starts = $ticket->Starts;
    unless ($starts) {
        $RT::Logger->info('Start date is not set.');
    }

    ## Check due date::
    my $due = $ticket->Due;
    unless ($due) {
        $RT::Logger->info('Due date is not set.');
    }

    ## Check configured priorities:
    my %priorities = RT->Config->Get('EscalateTicketsByPriority');
    unless ($priorities) {
        $RT::Logger->error(
            'Config: Information about escalating tickets by priority not set.'
        );
        return 0;
    }

    ## Check configured default priority:
    my $defaultPriority = RT->Config->Get('DefaultPriority');
    unless ($defaultPriority) {
        $RT::Logger->error('Config: Default priority not set.');
        return 0;
    }

    ## Validate default priority:
    if (!exists $priorities{$defaultPriority}) {
        $RT::Logger->error('Config: Default priority is not valid.');
        return 0;
    }

    ## Check configured Date::Manip:
    my %dateConfig = RT->Config->Get('DateManipConfig');
    unless (%dateConfig) {
        $RT::Logger->error('Config: Date::Manip\'s configuration not set.');
        return 0;
    }

    ## Check custom field:
    my $cfPriority = RT->Config->Get('PriorityField');
    my $cf = RT::CustomField->new($RT::SystemUser);
    $cf->LoadByNameAndQueue(Name => $cfPriority, Queue => '0');
    unless($cf->id) {
        $RT::Logger->error(
            'Config: Custom field ' . $cfPriority . ' does not exist.'
        );
        return 0;
    }

    return 1;
}

sub Commit {
    my $self = shift;

    my $ticket = $self->TicketObj;
    my $starts = $ticket->Starts;
    my $due = $ticket->Due;
    my $cfPriority = RT->Config->Get('PriorityField');
    my $priority = $ticket->FirstCustomFieldValue($cfPriority);

    ## Set default priority:
    unless($priority) {
        $priority = RT->Config->Get('DefaultPriority');
        my $cf = RT::CustomField->new($RT::SystemUser);
        $cf->LoadByNameAndQueue(Name => $cfPriority, Queue => $ticket->Queue);
        $ticket->AddCustomFieldValue(Field => $cf, Value => $priority);
    }

    my $date = new Date::Manip::Date;

    ## MySQL date time format:
    my $format = '%Y-%m-%d %T';

    ## Destinated default time to start is (simply) now:
    my $now  = 'now';

    ## Set start date:
    if (!$starts || $starts eq '1970-01-01 00:00:00') {
        $date->parse($now);
        $starts = $date->printf($format);

        my ($val, $msg) = $ticket->SetStarts($starts);
        unless ($val) {
            $RT::Logger->error('Could not set start date: ' . $msg);
            return 0;
        }
    }

    ## Set due date:
    unless (!$due || $due eq '1970-01-01 00:00:00') {
        ## Fetch when ticket should be escalated by priority:
        my %priorities = RT->Config->Get('EscalateTicketsByPriority');

        if (!exists $priorities{$priority}) {
            $RT::Logger->error('Unconfigured priority found: ' . $priority);
            return 0;
        }

        my $deltaStr = $priorities{$priority};

        ## Configure Date::Manip:
        my %dateConfig = RT->Config->Get('DateManipConfig');
        $date->config(%dateConfig);

        ## Compute date delta and format result:
        my $delta = $date->new_delta();
        $date->parse($starts);
        $delta->parse($deltaStr);
        my $calc = $date->calc($delta);
        $due = $calc->printf($format);

        my ($val, $msg) = $ticket->SetDue($due);
        unless ($val) {
            $RT::Logger->error('Could not set due date: ' . $msg);
            return 0;
        }
    }

    return 1;
}

1;
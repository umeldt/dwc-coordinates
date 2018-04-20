use strict;
use warnings;
use utf8;

use 5.14.0;

package DwC::Plugin::Coordinates;

our $VERSION = '0.01';

use Geo::Coordinates::UTM::XS;
use Geo::Coordinates::MGRS::XS qw(:all);
use Geo::Proj4;
use GeoCheck;

sub description {
  return "Converts MGRS, UTM and RT90 to decimal degrees";
}

sub handleMGRS {
  my ($plugin, $dwc) = @_;
  my $mgrs = $$dwc{coordinates} || $$dwc{verbatimCoordinates};
  my $datum = $$dwc{geodeticDatum};
  my ($lat, $lon);
  eval {
    if($datum eq "European 1950" || $$dwc{verbatimSRS} eq "ED50") {
      my ($zone, $h, $e, $n) = mgrs_to_utm($mgrs);
      my $ed50 = Geo::Proj4->new("+proj=utm +zone=$zone$h +ellps=intl \
        +units=m +towgs84=-87,-98,-121");
      my $wgs84 = Geo::Proj4->new(init => "epsg:4326");
      my $point = [$e, $n];
      ($lon, $lat) = @{$ed50->transform($wgs84, $point)};
      $$dwc{geodeticDatum} = "WGS84";
      $$dwc{decimalLatitude} = sprintf("%.5f", $lat);
      $$dwc{decimalLongitude} = sprintf("%.5f", $lon);
      $dwc->log("info",
        "MGRS (ED-50) coordinates converted to WGS84 latitude/longitude",
        "geography"
      );
    } else {
      my ($zone, $h, $e, $n) = mgrs_to_utm($mgrs);
      my $utm = Geo::Proj4->new("+proj=utm +zone=$zone$h +units=m");
      my $wgs84 = Geo::Proj4->new(init => "epsg:4326");
      my $point = [$e, $n];
      ($lon, $lat) = @{$utm->transform($wgs84, $point)};
      $dwc->log("info",
        "MGRS coordinates converted to WGS84 latitude/longitude", "geography");
      $$dwc{geodeticDatum} = "WGS84";
      $$dwc{decimalLatitude} = sprintf("%.5f", $lat);
      $$dwc{decimalLongitude} = sprintf("%.5f", $lon);
    }
  };
  if($@) {
    $dwc->log("warning",
      "Failed to convert MGRS coordinates: $mgrs", "geography");
    ($lat, $lon) = ("", "");
  }
}

sub handleUTM {
  my ($plugin, $dwc) = @_;

  my $coordinates = $$dwc{coordinates} || $$dwc{verbatimCoordinates};
  my ($zone, $e, $n) = split(/\s/, $coordinates, 3);
  if($$dwc{geodeticDatum} eq "European 1950" || $$dwc{verbatimSRS} eq "ED50") {
    my $ed50 = Geo::Proj4->new("+proj=utm +zone=$zone +ellps=intl +units=m \
      +towgs84=-87,-98,-121");
    if($ed50) {
      my $wgs84 = Geo::Proj4->new(init => "epsg:4326");
      my $point = [$e, $n];
      my ($lon, $lat) = @{$ed50->transform($wgs84, $point)};
      $$dwc{geodeticDatum} = "WGS84";
      $$dwc{decimalLatitude} = sprintf("%.5f", $lat);
      $$dwc{decimalLongitude} = sprintf("%.5f", $lon);
      $dwc->log("info", "UTM coordinates converted to WGS84 latitude/longitude",
        "geography");
    } else {
      $dwc->log("warning", "Broken UTM coordinates", "geography");
    }
  } else {
    my $proj = Geo::Proj4->new("+proj=utm +zone=$zone +units=m +ellps=WGS84");
    if($proj) {

      my $wgs84 = Geo::Proj4->new(init => "epsg:4326");
      my $point = [$e, $n];
      if(!$e || !$n) {
        $dwc->log("warning", "Missing coordinates", "geography");
      } else {
        my ($lon, $lat) = @{$proj->transform($wgs84, $point)};
        $$dwc{geodeticDatum} = "WGS84";
        $$dwc{decimalLatitude} = sprintf("%.5f", $lat);
        $$dwc{decimalLongitude} = sprintf("%.5f", $lon);
        $dwc->log("info",
          "UTM coordinates converted to WGS84 latitude/longitude", "geography");
      }
    } else {
      $dwc->log("warning", "Invalid UTM zone: $zone", "geography");
    }
  }
}

sub handleRT90 {
  my ($plugin, $dwc) = @_;
  eval {
    $SIG{__WARN__} = sub { die @_; };
    my $rt90 = Geo::Proj4->new(init => "epsg:2400");
    my $wgs84 = Geo::Proj4->new(init => "epsg:4326");
    my ($n, $e) = split /[\s,]/, $$dwc{verbatimCoordinates};

    if(!$$dwc{coordinateUncertaintyInMeters}) {
      my $l = length($e);
      if($l == 7) {
        $$dwc{coordinateUncertaintyInMeters} = 1;
      } elsif($l == 6) {
        $$dwc{coordinateUncertaintyInMeters} = 10;
      } elsif($l == 5) {
        $$dwc{coordinateUncertaintyInMeters} = 100;
      } elsif($l == 4) {
        $$dwc{coordinateUncertaintyInMeters} = 1000;
      } elsif($l == 3) {
        $$dwc{coordinateUncertaintyInMeters} = 10000;
      } elsif($l == 2) {
        $$dwc{coordinateUncertaintyInMeters} = 100000;
      } elsif($l == 1) {
        $$dwc{coordinateUncertaintyInMeters} = 1000000;
      }
    }

    $e = $e . "0" while(length($e) < 7);
    $n = $n . "0" while(length($n) < 7);
    my ($lon, $lat) = @{$rt90->transform($wgs84, [$e, $n])};
    $$dwc{geodeticDatum} = "WGS84";
    $$dwc{decimalLatitude} = sprintf("%.5f", $lat);
    $$dwc{decimalLongitude} = sprintf("%.5f", $lon);
    $dwc->log("info",
      "RT90 coordinates converted to decimal degrees", "geography");
  };
  if($@) {
    $dwc->log("warning",
      "Unable to handle RT90 coordinates ($$dwc{verbatimCoordinates}",
      "geography");
  }
}

sub clean {
  my ($plugin, $dwc) = @_;
  return unless($$dwc{verbatimCoordinateSystem});
  if($$dwc{verbatimCoordinateSystem} eq "MGRS") {
    $plugin->handleMGRS($dwc);
  } elsif($$dwc{verbatimCoordinateSystem} eq "UTM") {
    $plugin->handleUTM($dwc);
  } elsif($$dwc{verbatimCoordinateSystem} eq "RT90") {
    $plugin->handleRT90($dwc);
  }
}

sub validate {
  my ($plugin, $dwc) = @_;
  my ($lat, $lon) = ($$dwc{decimalLatitude}, $$dwc{decimalLongitude});
  if ($lat && ($lat < -90 || $lat > 90)) {
    $dwc->log("warning", "Latitude $lat out of bounds", "geography");
  }
  if ($lon && ($lon < -180 || $lon > 360)) {
    $dwc->log("warning", "Longitude $lon out of bounds", "geography");
  }
  eval {
    my ($lat, $lon) = ($$dwc{decimalLatitude}, $$dwc{decimalLongitude});
    my $prec = $$dwc{coordinateUncertaintyInMeters};
    my $pol;

    return if(!$lat || !$lon || $lat == 0 || $lon == 0);

    if($$dwc{stateProvince} && $$dwc{county}) {
      my $county = $$dwc{county};
      my $state = $$dwc{stateProvince};
      my $id = "$state-$county";

      return if GeoCheck::inside($id, $lat, $lon);
      my ($p, $d) = GeoCheck::distance($id, $lat, $lon);
      return if($prec && $d < $prec);
      $pol = GeoCheck::polygon($id);
      $d = int($d);

      my $sug = GeoCheck::georef($lat, $lon, 'county');
      if($sug eq $county) {
        $dwc->log("info", "Matched secondary polygon...", "dev");
      } elsif($sug) {
        $dwc->log("warning", "$d meters outside $county ($sug?)", "geography");
      } else {
        $dwc->log("warning", "$d meters outside $county", "geography");
      }
      $dwc->log("info", $pol, "geography") if $pol;
    }

    if($$dwc{stateProvince}) {
      my $id = $$dwc{stateProvince};
      return if GeoCheck::inside($id, $lat, $lon);
      my ($p, $d) = GeoCheck::distance($id, $lat, $lon);
      return if($prec && $d < $prec);
      $pol = GeoCheck::polygon($id);
      $d = int($d);
      my $sp = $$dwc{stateProvince};
      my $sug = GeoCheck::georef($lat, $lon, 'stateprovince');
      if($sug eq $sp) {
        $dwc->log("info", "Matched secondary polygon...", "dev");
      } elsif($sug) {
        $dwc->log("warning", "$d meters outside $sp ($sug?)", "geography");
      } else {
        $dwc->log("warning", "$d meters outside $sp", "geography");
      }
      $dwc->log("info", $pol, "geography") if $pol;
    }
  };
}

1;

__END__

=head1 NAME

DwC::Plugin::Coordinates - converts MGRS, UTM and RT90 to decimal degrees

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2018 by umeldt

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.24.4 or,
at your option, any later version of Perl 5 you may have available.

=cut

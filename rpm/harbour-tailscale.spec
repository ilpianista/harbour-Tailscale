Name:       harbour-tailscale

# >> macros
%global _missing_build_ids_terminate_build 0
%define tailscale_version 1.92.5
# << macros

%{!?qtc_qmake:%define qtc_qmake %qmake}
%{!?qtc_qmake5:%define qtc_qmake5 %qmake5}
%{!?qtc_make:%define qtc_make make}
%{?qtc_builddir:%define _builddir %qtc_builddir}
Summary:    tailscale
Version:    0.0.9
Release:    1
Group:      Qt/Qt
License:    GPLv3
URL:        https://scarpino.dev
Source0:    %{name}-%{version}.tar.bz2
%ifarch %arm
Source1: tailscale_%{tailscale_version}_arm.tgz
%endif
%ifarch aarch64
Source1: tailscale_%{tailscale_version}_arm64.tgz
%endif
%ifarch %ix86
Source1: tailscale_%{tailscale_version}_386.tgz
%endif
Source2:    tailscaled.service
Source3:    tailscaled.defaults
Requires:   sailfishsilica-qt5 >= 0.10.9
BuildRequires:  pkgconfig(sailfishapp) >= 1.0.2
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  desktop-file-utils

%ifarch %arm
%define tailscale_dir tailscale_%{tailscale_version}_arm
%endif
%ifarch aarch64
%define tailscale_dir tailscale_%{tailscale_version}_arm64
%endif
%ifarch %ix86
%define tailscale_dir tailscale_%{tailscale_version}_386
%endif

%description

Tailscale makes networking easy

%prep
%setup -q -n %{name}-%{version}

#%setup -a 1 doesn't work in mb2
if [ ! -d %{tailscale_dir} ]; then
  tar xf %{SOURCE1}
fi

# >> setup
# << setup

%build
# >> build pre
# << build pre

%qtc_qmake5

%qtc_make %{?_smp_mflags}

# >> build post
# << build post

%install
rm -rf %{buildroot}
# >> install pre
# << install pre
%qmake5_install

# >> install post
install -d %{buildroot}%{_unitdir}
install -m644 %{SOURCE2} %{buildroot}%{_unitdir}

install -m755 %{tailscale_dir}/tailscale %{buildroot}%{_bindir}
install -m755 %{tailscale_dir}/tailscaled %{buildroot}%{_bindir}

install -d %{buildroot}%{_sharedstatedir}/tailscale
install -d %{buildroot}%{_localstatedir}/cache/tailscale

install -d %{buildroot}%{_sysconfdir}/sysconfig
install -Dm644 %{SOURCE3} %{buildroot}%{_sysconfdir}/sysconfig/tailscaled
# << install post

desktop-file-install --delete-original       \
  --dir %{buildroot}%{_datadir}/applications             \
   %{buildroot}%{_datadir}/applications/*.desktop

%files
%defattr(-,root,root,-)
%attr(4755,root,root) %{_bindir}/%{name}
%{_bindir}/tailscale
%{_bindir}/tailscaled
%{_datadir}/%{name}
%{_sysconfdir}/sysconfig/tailscaled
%{_unitdir}/tailscaled.service
%dir %{_sharedstatedir}/tailscale
%dir %{_localstatedir}/cache/tailscale
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png
# >> files
# << files

%post
systemctl daemon-reload

%preun
if [ $1 -eq 0 ]; then
  systemctl stop tailscaled.service
  systemctl disable tailscaled.service
fi

%postun
systemctl daemon-reload

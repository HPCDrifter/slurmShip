#!/usr/bin/env bash
set -e

# Setup RPM build environment with custom macros
echo "Setting up RPM build environment with custom configuration..."

# Ensure rpmbuild directory structure exists
mkdir -p /root/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

# build slurm rpms with custom macro configuration
echo "Downloading SLURM ${SLURM_VERSION} source..."
wget https://download.schedmd.com/slurm/slurm-${SLURM_VERSION}.tar.bz2

echo "Building SLURM RPMs with custom configuration..."
rpmbuild -ta "slurm-${SLURM_VERSION}.tar.bz2"

echo "Copying SLURM RPMs to output directory..."
cp /root/rpmbuild/RPMS/${ARCH}/slurm-* /packages

echo "SLURM RPMs built successfully:"
ls -la /packages/slurm-*

# build openmpi rpm
echo "Setting up OpenMPI build environment..."
mkdir -p /usr/src/redhat
ln -sf /root/rpmbuild/SOURCES /usr/src/redhat/SOURCES
ln -sf /root/rpmbuild/SPECS   /usr/src/redhat/SPECS
ln -sf /root/rpmbuild/RPMS    /usr/src/redhat/RPMS
ln -sf /root/rpmbuild/SRPMS   /usr/src/redhat/SRPMS

# fetch tarball + build script
echo "Downloading OpenMPI ${OPENMPI_VERSION} source..."
wget https://download.open-mpi.org/release/open-mpi/${OPENMPI_VERSION}/${OPENMPI_RPM}
curl -sSL https://raw.githubusercontent.com/open-mpi/ompi/${OPENMPI_VERSION}.x/contrib/dist/linux/buildrpm.sh -o buildrpm.sh
chmod +x buildrpm.sh

# install slurm RPMs so OpenMPI can build with slurm support
echo "Installing SLURM RPMs for OpenMPI build dependency..."
yum -y localinstall /root/rpmbuild/RPMS/${ARCH}/slurm-*

# copy tarball into SOURCES (must match specfile name)
cp ${OPENMPI_RPM} /root/rpmbuild/SOURCES/

# run buildrpm.sh with proper configure options (PMIx required)
echo "Building OpenMPI RPMs with SLURM and PMIx support..."
./buildrpm.sh -b -s -c "--with-slurm --with-pmix" ${OPENMPI_RPM}

# copy built RPMs to /packages
echo "Copying OpenMPI RPMs to output directory..."
cp /root/rpmbuild/RPMS/${ARCH}/openmpi-* /packages

echo "OpenMPI RPMs built successfully:"
ls -la /packages/openmpi-*

echo "Build process completed successfully!"
echo "All built packages:"
ls -la /packages/

exec "$@"

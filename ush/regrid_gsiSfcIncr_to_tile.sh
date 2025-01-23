#! /usr/bin/env bash

source "${USHgfs}/preamble.sh"

#-------------------------------------------------------------------------------------------------
# Script to regrid surface increment from GSI grid 
# to fv3 tiles. 
# Clara Draper, Dec 2024
#-------------------------------------------------------------------------------------------------

export PGMOUT=${PGMOUT:-${pgmout:-'&1'}}
export PGMERR=${PGMERR:-${pgmerr:-'&2'}}
export REDOUT=${REDOUT:-'1>'}
export REDERR=${REDERR:-'2>'}

REGRID_EXEC=${HOMEgfs}/exec/regridStates.x
#sorc/gdas.cd/build/bin/regridStates.x

export PGM=$REGRID_EXEC
export pgm=$PGM

NMEM_REGRID=${NMEM_REGRID:-1}
CASE_IN=${CASE_IN:-$CASE_ENS}

# get resolutions
CRES_IN=$(echo $CASE_IN | cut -c2-)
LONB_CASE_IN=$((4*CRES_IN))
LATB_CASE_IN=$((2*CRES_IN))

CRES_OUT=$(echo $CASE_OUT | cut -c2-)
ntiles=6

APREFIX="${RUN/enkf}.t${cyc}z."
APREFIX_ENS="enkfgdas.t${cyc}z."

n_vars=$((LSOIL_INCR*2))

# TODO: input this through config?
var_list_in=""
#var_list_in="soilt1_inc","slc1_inc","","","","","","","","",
for vi in $( seq 1 ${LSOIL_INCR} ); do
    var_list_in=${var_list_in}'"soilt'${vi}'_inc"',   
done
for vi in $( seq 1 ${LSOIL_INCR} ); do
    var_list_in=${var_list_in}'"slc'${vi}'_inc"',
done

# tempory fix till reg ouputs time dim
sfiprfx="sfci00["  #"sfci00[369]"  ##only for single digit hours
landinc_fhr_f=""
dlmtr=""
IFS=',' read -ra landifhrs <<< "${LAND_IAU_FHRS}"
for ihr in "${landifhrs[@]}"; do
    hrsf=$(printf "%.1f" "$ihr")
    landinc_fhr_f="${landinc_fhr_f}${dlmtr}${hrsf}"
    dlmtr=","
    sfiprfx="${sfiprfx}${ihr}"
done
sfiprfx="${sfiprfx}]"

# fixed input files
# TODO: copy this to fix dir for all res?
ln -sf /scratch2/BMC/gsienkf/Clara.Draper/regridding/inputs/gaussian.${LONB_CASE_IN}.${LATB_CASE_IN}.nc gaussian_scrip.nc

# fixed output files
for n in $(seq 1 $ntiles); do
    ln -sf ${FIXorog}/${CASE_OUT}/sfc/${CASE_OUT}.mx${OCNRES_OUT}.vegetation_type.tile${n}.nc  vegetation_type.tile${n}.nc
done

rm -f regrid.nml

cat > regrid.nml << EOF
&config
 n_vars=${n_vars},
 variable_list=${var_list_in}
 missing_value=0.,
/

&input
  gridtype="gau_inc",
  ires=${LONB_CASE_IN},
  jres=${LATB_CASE_IN},
  fname=enkfgdas.sfci.nc,
  dir="./",
  fname_coord="gaussian_scrip.nc",
  dir_coord="./"
/

&output
  gridtype="fv3_rst",
  ires=${CRES_OUT},
  jres=${CRES_OUT},
  fname="sfci",
  dir="./",
  fname_mask="vegetation_type" 
  dir_mask="./"
  dir_coord="$FIXorog",
/
EOF

for imem in $(seq 1 $NMEM_REGRID); do
    if [[ $NMEM_REGRID > 1 ]]; then
        cmem=$(printf %03i $imem)
        memchar="mem$cmem"
     
        MEMDIR=${memchar} YMD=${PDY} HH=${cyc} declare_from_tmpl \
            COM_ATMOS_ANALYSIS_MEM:COM_ATMOS_ANALYSIS_TMPL

        COM_SOIL_ANALYSIS_MEM=$COM_ATMOS_ANALYSIS_MEM
    fi
 
    for FHR in ${landinc_reghrs}; do
        ln -fs ${COM_SOIL_ANALYSIS_MEM}/${APREFIX_ENS}sfci0${FHR}.nc \
                ${DATA}/enkfgdas.sfci.nc

        ${APRUN_REGR} $REGRID_EXEC $REDOUT$PGMOUT $REDERR$PGMERR

        for n in $(seq 1 $ntiles); do
            mv sfci.tile${n}.nc  sfci0${FHR}.tile${n}.nc 
        done
    done
    #TODO: TZG temp fix till reg ouputs time dim
    for n in $(seq 1 $ntiles); do
        ncecat -u Time ${sfiprfx}.tile${n}.nc sfc_inc.tile${n}.nc   #sfci00[369]
	ncap2 -A -s @all="{${landinc_fhr_f[@]}}" sfc_inc.tile${n}.nc sfc_inc.tile${n}.nc
	ncap2 -O -s'Time[Time]=@all' sfc_inc.tile${n}.nc sfc_inc.tile${n}.nc

        for FHR in ${landinc_reghrs}; do
	    yes |cp -u ${DATA}/sfci0${FHR}.tile${n}.nc  ${COM_ATMOS_ANALYSIS_MEM}/sfci0${FHR}.tile${n}.nc
	    rm -f ${DATA}/sfci0${FHR}.tile${n}.nc
	done
	yes |cp -u  ${DATA}/sfc_inc.tile${n}.nc  ${COM_ATMOS_ANALYSIS_MEM}/sfc_inc.tile${n}.nc
	rm -f ${DATA}/sfc_inc.tile${n}.nc
    done
done

exit 0


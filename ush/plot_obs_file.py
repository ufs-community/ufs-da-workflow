#!/usr/bin/env python3

###################################################################### CHJ #####
## Name		  : plot_obs_file.py
## Usage	  : Plot observation data file of land-DA workflow
## NOAA/EPIC
## History ===============================
## V000: 2024/12/03: Chan-Hoo Jeon : Preliminary version
## V001: 2025/04/17: Chan-Hoo Jeon : Add IMS option
## V002: 2025/11/13: Chan-Hoo Jeon : Add SOCA option
###################################################################### CHJ #####

import os, sys
import logging
import yaml
import numpy as np
import netCDF4 as nc
import cartopy
import cartopy.crs as ccrs
import cartopy.feature as cfeature
import matplotlib.pyplot as plt
from mpl_toolkits.axes_grid1 import make_axes_locatable


# Main part (will be called at the end) ============================= CHJ =====
def main():

    yaml_file="plot_obs_file.yaml"
    with open(yaml_file, 'r') as f:
        yaml_data=yaml.load(f, Loader=yaml.FullLoader)
    f.close()

    work_dir = yaml_data['work_dir']
    cartopy_ne_path = yaml_data['cartopy_ne_path']
    TYPE_ANAL_FCST = yaml_data['TYPE_ANAL_FCST']
    JEDI_TYPE_FV3 = yaml_data['JEDI_TYPE_FV3']
    JEDI_TYPE_SOCA = yaml_data['JEDI_TYPE_SOCA']
    OBS_SNOW_GHCN = yaml_data['OBS_SNOW_GHCN']
    OBS_SNOW_IMS = yaml_data['OBS_SNOW_IMS']
    OBS_SWC_SMAP = yaml_data['OBS_SWC_SMAP']
    OBS_SWC_SMOPS = yaml_data['OBS_SWC_SMOPS']
    obs_prefix = yaml_data['obs_prefix']
    PDY = yaml_data['PDY']
    PY_LOG_LEVEL = yaml_data['PY_LOG_LEVEL']
    
    # Set logging config
    log_level_str = PY_LOG_LEVEL.upper()
    try:
        log_level = getattr(logging, log_level_str)
    except AttributeError:
        log_level_str = "INFO"
        log_level = logging.INFO
        print(f''' WARNING: Invalid log level "{PY_LOG_LEVEL.upper()}", set to INFO.''')
    print(f''' Python Log Level= str: {log_level_str}, attr: {log_level}''')
    logging.basicConfig(format='%(levelname)s::%(pathname)s::L%(lineno)d::%(message)s', level=log_level)

    logging.info(f''' YAML Data: {yaml_data}''')

    # Set the path to Natural Earth dataset
    cartopy.config['data_dir']=cartopy_ne_path

    # Plot GHCN
    if OBS_SNOW_GHCN == "YES":
        obs_plot("ghcn",PDY,work_dir,obs_prefix,"ghcn_snow")
    # Plot IMS
    if OBS_SNOW_IMS == "YES":
        obs_plot("ims",PDY,work_dir,obs_prefix,"ims_snow.tm00")
    # Plot SMAP
    if OBS_SWC_SMAP == "YES":
        obs_plot("smap",PDY,work_dir,obs_prefix,"smap_combined")
    # Plot SMOPS
    if OBS_SWC_SMOPS == "YES":
        obs_plot("smops",PDY,work_dir,obs_prefix,"smops")
    # Plot SOCA
    if JEDI_TYPE_SOCA == "YES":
        if TYPE_ANAL_FCST == "ctest":
            obs_plot("soca_sst",PDY,work_dir,obs_prefix,"sst")
            obs_plot("soca_sss",PDY,work_dir,obs_prefix,"sss")
            obs_plot("soca_adt",PDY,work_dir,obs_prefix,"adt")
            obs_plot("soca_prof_t",PDY,work_dir,obs_prefix,"prof")
            obs_plot("soca_prof_s",PDY,work_dir,obs_prefix,"prof")
            obs_plot("soca_icec",PDY,work_dir,obs_prefix,"icec")
        else:
            obs_plot("soca_adt",PDY,work_dir,obs_prefix,"adt_ssh")
            obs_plot("soca_sst",PDY,work_dir,obs_prefix,"sst_satellite")
            obs_plot("soca_sss",PDY,work_dir,obs_prefix,"sss_salinity")
            obs_plot("soca_prof_t",PDY,work_dir,obs_prefix,"prof_insitu")
            obs_plot("soca_prof_s",PDY,work_dir,obs_prefix,"prof_insitu")
    # Plot FV3-JEDI
    if JEDI_TYPE_FV3 == "YES":
        if TYPE_ANAL_FCST == "ctest":
            obs_plot("fv3_geos",PDY,work_dir,obs_prefix,"tropomi_no2")


# obs plot =============================================== CHJ =====
def obs_plot(obs_type,PDY,work_dir,fn_prefix,fn_suffix):

    # open the data file
    fn_input = f'''{fn_prefix}.{fn_suffix}.nc'''
    logging.info(f''' ===== INPUT:: {obs_type}:: '{fn_input}' ================================''')
    fpath = os.path.join(work_dir,fn_input)
    try: mdat = nc.Dataset(fpath)
    except: raise Exception('Could NOT find the file',fpath)

    logging.debug(" MetaData:", mdat.groups['MetaData'])
    logging.debug(" ObsValue:", mdat.groups['ObsValue'])

    lon = mdat.groups['MetaData'].variables['longitude'][:]
    lat = mdat.groups['MetaData'].variables['latitude'][:]
    # Variables
    #vars_out=["ObsValue", "ObsError", "PreQC"]
    vars_out=["ObsValue"]

    # Highest and lowest longitudes and latitudes for plot extent
    lon_min=np.min(lon)
    lon_max=np.max(lon)
    lat_min=np.min(lat)
    lat_max=np.max(lat)
    logging.info(f''' lon min,max = {lon_min}, {lon_max}''')
    logging.info(f''' lat min,max = {lat_min}, {lat_max}''')

    #extent=[lon_min,lon_max,lat_min,lat_max]
    extent=[]
    if obs_type == "fv3_geos":
        # for CONUS
        extent=[-125,-66,23,53]
    else:
        # for Northern Hemisphere (default)
        extent=[-179,179,0,82.5]
    logging.info(f''' Map extent= {extent}''')

    #c_lon=np.mean(extent[:2])
    c_lon=-77.0369 # D.C.
    logging.info(f''' c_lon= {c_lon}''')

    for svar in vars_out:
        svar_plot(svar,mdat,lon,lat,c_lon,extent,obs_type,PDY,work_dir)
    

# Variable plot =============================================== CHJ =====
def svar_plot(svar,mdat,lon,lat,c_lon,extent,obs_type,PDY,work_dir):

    logging.info(' ===== '+svar+' ==========================================')

    cs_cmap='gist_ncar_r'
    lb_ext='neither'
    tick_ln=1.5
    tick_wd=0.45
    tlb_sz=3
    n_rnd=2
    cmap_range='fixed'
    scat_sz=1.0

    # Extract data array
    if obs_type == "smap" or obs_type == "smops":
        gvar = "soilMoistureVolumetric"
        pvar = "Soil Moisture"
    elif obs_type == "ghcn" or obs_type == "ims":
        gvar = "totalSnowDepth"
        pvar = "Snow Depth"
    elif obs_type == "soca_sst":
        gvar = "seaSurfaceTemperature"
        pvar = "Sea Surface Temperature"
    elif obs_type == "soca_sss":
        gvar = "seaSurfaceSalinity"
        pvar = "Sea Surface Salinity"
    elif obs_type == "soca_adt":
        gvar = "absoluteDynamicTopography"
        pvar = "Absolute Dynamic Topography"
    elif obs_type == "soca_icec":
        gvar = "seaIceFraction"
        pvar = "Sea Ice Fraction"
    elif obs_type == "soca_prof_t":
        gvar = "waterTemperature"
        pvar = "Insitu Temperature"
    elif obs_type == "soca_prof_s":
        gvar = "salinity"
        pvar = "Insitu Salinity"
    elif obs_type == "fv3_geos":
        gvar = "nitrogendioxideColumn"
        pvar = "Nitrogen dioxide (NO2)"
    else:
        gvar = svar
        pvar = svar

    sfld = mdat.groups[svar].variables[gvar][:]

    obs_type_upper = obs_type.upper()
    out_title_fld = f'''UFS-DA::Obs::{obs_type_upper}::{PDY}::{pvar}'''
    out_fn = f'''ufsda_obs_{obs_type}_{PDY}_{gvar}'''

    # Check array size
    lon_len = len(lon)
    lat_len = len(lat)
    sfld_len = len(sfld)
    logging.info(f''' length of lon = {lon_len}''')
    logging.info(f''' length of lat = {lat_len}''')
    logging.info(f''' lenght of sfld = {sfld_len}''')
    if lon_len != lat_len or lon_len != sfld_len or lat_len != sfld_len:
        sys.exit('FATAL ERROR: array size mismatched !!!')

    # Max and Min of the field
    fmax = np.max(sfld)
    fmin = np.min(sfld)
    logging.info(f''' Max of {pvar}= {fmax}''')
    logging.info(f''' Min of {pvar}= {fmin}''')

    # Make the colormap range symmetry
    logging.info(f''' cmap range= {cmap_range}''')
    if cmap_range=='symmetry':
        tmp_cmp=max(abs(fmax),abs(fmin))
        cs_min=round(-tmp_cmp,n_rnd)
        cs_max=round(tmp_cmp,n_rnd)
    elif cmap_range=='round':
        cs_min=round(fmin,n_rnd)
        cs_max=round(fmax,n_rnd)
    elif cmap_range=='real':
        cs_min=fmin
        cs_max=fmax
    elif cmap_range=='fixed':
        cs_min=0
        if obs_type == 'ims':
            cs_max=100.0
        elif obs_type == 'ghcn':
            cs_max=1000.0
        elif obs_type == 'smap' or obs_type == 'smops':
            cs_max=1.0
            cs_min=0.0
        elif obs_type == 'soca_sst' or obs_type == 'soca_prof_t':
            cs_max = 35
            cs_min = -5
        elif obs_type == 'soca_sss' or obs_type == 'soca_prof_s':
            cs_max = 38
            cs_min = 30
        elif obs_type == 'soca_adt':
            cs_max = 1.4
            cs_min = -1.4
            cs_cmap = 'turbo'
        elif obs_type == 'soca_icec':
            cs_max = 1
            cs_min = 0
        elif obs_type == 'fv3_geos':
            cs_max = 3e-05
            cs_min = 0
        else:
            cs_max=300.0
    else:
        sys.exit('FATAL ERROR: wrong colormap-range flag !!!')

    logging.info(f''' cs_max= {cs_max}''')
    logging.info(f''' cs_min= {cs_min}''')

    # Plot field
    fig,ax=plt.subplots(1,1,subplot_kw=dict(projection=ccrs.Robinson(c_lon)))
    if obs_type == "ghcn" or obs_type == "fv3_geos":
        ax.set_extent(extent, ccrs.PlateCarree())
    else:
        ax.set_global()

    # Call background plot
    back_plot(ax)
    ax.set_title(out_title_fld,fontsize=8)
    cs=ax.scatter(lon,lat,transform=ccrs.PlateCarree(),c=sfld,cmap=cs_cmap,
                  vmin=cs_min,vmax=cs_max,s=scat_sz)
    divider=make_axes_locatable(ax)
    ax_cb=divider.new_horizontal(size="3%",pad=0.1,axes_class=plt.Axes)
    fig.add_axes(ax_cb)
    cbar=plt.colorbar(cs,cax=ax_cb,extend=lb_ext)
    cbar.ax.tick_params(labelsize=7)
    cbar.set_label(pvar,fontsize=7)

    # Output figure
    ndpi=300
    out_file(work_dir,out_fn,ndpi)


# Background plot ==================================================== CHJ =====
def back_plot(ax):
    # Resolution of background natural earth data ('50m' or '110m')
    back_res='50m'

    fline_wd=0.5  # line width
    falpha=0.7 # transparency

    # natural_earth
    land=cfeature.NaturalEarthFeature('physical','land',back_res,
                      edgecolor='face',facecolor=cfeature.COLORS['land'],
                      alpha=falpha)
    lakes=cfeature.NaturalEarthFeature('physical','lakes',back_res,
                      edgecolor='blue',facecolor='none',
                      linewidth=fline_wd,alpha=falpha)
    coastline=cfeature.NaturalEarthFeature('physical','coastline',
                      back_res,edgecolor='black',facecolor='none',
                      linewidth=fline_wd,alpha=falpha)
    states=cfeature.NaturalEarthFeature('cultural','admin_1_states_provinces',
                      back_res,edgecolor='green',facecolor='none',
                      linewidth=fline_wd,linestyle=':',alpha=falpha)
    borders=cfeature.NaturalEarthFeature('cultural','admin_0_countries',
                      back_res,edgecolor='red',facecolor='none',
                      linewidth=fline_wd,alpha=falpha)

#    ax.add_feature(land)
#    ax.add_feature(lakes)
#    ax.add_feature(states)
#    ax.add_feature(borders)
    ax.add_feature(coastline)


# Output file ======================================================= CHJ =====
def out_file(work_dir,out_file,ndpi):
    # Output figure
    fp_out=os.path.join(work_dir,out_file)
    plt.savefig(fp_out+'.png',dpi=ndpi,bbox_inches='tight')
    plt.close('all')


# Main call ========================================================= CHJ =====
if __name__=='__main__':
    main()


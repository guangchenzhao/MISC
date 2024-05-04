setwd("/home/rstudio")
install.packages("aws.s3")
install.packages('data.table')
install.packages('plyr')
install.packages('dplyr')
install.packages('R.utils')
install.packages('sp')
install.packages('doSNOW')
install.packages('dbscan')
install.packages('rgdal')
install.packages('geosphere')
install.packages('lutz')
install.packages('lubridate')
library(doSNOW)
library(data.table)
library(plyr)
library(dplyr)
library(R.utils)
library(sp)
library(dbscan)
library(rgdal)
library(geosphere)
library(lutz)
library(lubridate)
library(aws.s3)

#2020 0614_0620
# determine selected dates
datelist=c("inbound/2020/06/14/",
           "inbound/2020/06/15/",
           "inbound/2020/06/16/",
           "inbound/2020/06/17/",
           "inbound/2020/06/18/",
           "inbound/2020/06/19/",
           "inbound/2020/06/20/")

#get access to the s3 bucket containing raw data
Sys.setenv("AWS_ACCESS_KEY_ID" = "",
           "AWS_SECRET_ACCESS_KEY" = "")

#creat folders
dir.create("/home/rstudio/provider")
dir.create("/home/rstudio/provider/raw data")
dir.create("/home/rstudio/provider/Data products")
dir.create("/home/rstudio/provider/Data products/0614_0620")
dir.create("/home/rstudio/provider/Data products/0614_0620/forupload")
dir.create("/home/rstudio/provider/Data products/0614_0620/raw points")
dir.create("/home/rstudio/provider/Data products/0614_0620/home location")
dir.create("/home/rstudio/provider/Data products/0614_0620/Device list")
dir.create("/home/rstudio/provider/Data products/0614_0620/data_by_device_id")

#download raw data from s3 bucket
downloadfroms3=function(core){
  s3sync(
    path = "/home/rstudio/provider/raw data",
    'xx',
    prefix = datelist[core],
    direction = "download",
    verbose = TRUE,
    create = FALSE,
  )
}

start=Sys.time()

cl = makeCluster(7)
registerDoSNOW(cl)
getDoParWorkers()
foreach(core=1:7,.packages = c('plyr','sp','dplyr','R.utils','aws.s3'))%dopar%{
  downloadfroms3(core)
}
stopCluster(cl)
rm(cl)
closeAllConnections()
gc()

end=Sys.time()
end-start



# Read and open gz file
readgz = function(files){
  table <- fread(files)
  
  # Select columns
  #2020
  table <- subset(table, select=-c(os,ip_address,connection_type,event_type,gps_speed,country_iso3,carrier,make,model,app_id,org_id,Place_name,placeID,Category))
  
  return(table)
}

# Define path with all zipped files
mypath ="/home/rstudio/provider/raw data"

zipF <- list.files(path = mypath, pattern = "*.gz", full.names = TRUE)


data_reading_cleaning=function(core){
  
  # Read zipped files and extract data, create combined dataset
  j=formatC(core, width = 3, format = "d", flag = "0")
  
  data= readgz(zipF[core])
  data = unique(data,by=c("maid","utc_timestamp"))
  ID_fl=unique(data$maid)
  fwrite(data,paste0("/home/rstudio/provider/Data products/0614_0620/raw points/raw_points_",j,".csv"))
  fwrite(as.data.table(ID_fl),paste0("/home/rstudio/provider/Data products/0614_0620/Device list/Raw_Device_",j,"_tmp.csv"))
  
}

start=Sys.time()
#Run the Extraction function in Parallel
for (loop_id in 0:13){
  cl = makeCluster(32)
  registerDoSNOW(cl)
  getDoParWorkers()
  print(loop_id)
  foreach(core=((loop_id*32+1):((loop_id+1)*32)),.packages = c('data.table','plyr','sp','dplyr','R.utils'))%dopar%{
    data_reading_cleaning(core)
  }
  stopCluster(cl)
  rm(cl)
  closeAllConnections()
  gc()
}
end=Sys.time()

##############################################################################################################
# list of unique devices of data
mypath ="/home/rstudio/provider/Data products/0614_0620/raw points"
zipF <- list.files(path = mypath,pattern = ".csv", full.names = TRUE)

mypath1 ="/home/rstudio/provider/Data products/0614_0620/Device list"
zipF1 <- list.files(path = mypath1,pattern = "tmp.csv", full.names = TRUE)
IDlist=data.table()
for (i in 1:448){
  ID_fl=fread(zipF1[i],fill = TRUE)
  IDlist=rbind(IDlist,ID_fl)
  file.remove(zipF1[i])
}
unique_ID=unique(IDlist$ID_fl)
IDlist=data.table()
unique_ID=as.data.table(unique_ID)
unique_ID=unique_ID[order(unique_ID),]
fwrite(as.data.table(unique_ID),"/home/rstudio/provider/Data products/0614_0620/unique_ID.csv")


#Data based on device subgroups
for(core in 0:999){
  b=unique_ID[(round(core/1000*length(unique_ID))+1):(round((core+1)/1000*length(unique_ID)))]
  b=as.data.table(b)
  colnames(b)=("maid")
  j=formatC(core, width = 3, format = "d", flag = "0")
  
  fwrite(b,paste0("/home/rstudio/provider/Data products/0614_0620/Device list/Raw_Device_",j,".csv"))
}


#Extraction Function
device_observation_extraction=function(core){
  core=formatC(core, width = 3, format = "d", flag = "0")
  
  device1=fread(paste0("/home/rstudio/provider/Data products/0614_0620/Device list/Raw_Device_",core,".csv"))
  
  data_by_device1=data.table()
  
  for (i in 1:448){
    print(i)
    data=fread(zipF[i],fill = TRUE)

    data1=data[maid %in% device1$maid]
    data_by_device1=rbind(data_by_device1,data1)

  }
  data_by_device1 = unique(data_by_device1,by=c("maid","utc_timestamp"))
  fwrite(data_by_device1,paste0("/home/rstudio/provider/Data products/0614_0620/data_by_device_id/extracted_observation_device",core,".csv"))

}
start=Sys.time()
#Run the Extraction function in Parallel
for (loop_id in 0:49){
  cl = makeCluster(20)
  registerDoSNOW(cl)
  getDoParWorkers()
  print(loop_id)
  foreach(core=((loop_id*20):((loop_id+1)*20-1)),.packages = c('data.table'))%dopar%{
    device_observation_extraction(core)
  }
  stopCluster(cl)
  rm(cl)
  closeAllConnections()
  gc()
}
end=Sys.time()
end-start


# DB-SCAN
# timezone offset list
tz_list =tz_list()

#daylight saving time
tz_list=tz_list[!duplicated(tz_list$tz_name,fromLast = TRUE),]
# #not daylight saving time
# tz_list=tz_list[!duplicated(tz_list$tz_name,fromLast = FALSE),]

tz_list=tz_list[,c("tz_name","utc_offset_h")]

home_location_identification=function(core){

  j=formatC(core, width = 3, format = "d", flag = "0")
  
  device_data=fread(paste0("/home/rstudio/provider/Data products/0614_0620/data_by_device_id/extracted_observation_device",j,".csv"))
  device_data$tz_name=tz_lookup_coords(device_data$lat, device_data$lon)
  device_data=merge(device_data,tz_list,by='tz_name',all.x=TRUE)
  device_data$local_timestamp=as.POSIXct(device_data$utc_timestamp)+3600*device_data$utc_offset_h
  device_data$time1=format(device_data$local_timestamp,"%H:%M:%S")
  
  #Filtering data between 7 pm to 7 am
  am=device_data[time1>="00:00:00" & time1 <="07:00:00"]
  pm=device_data[time1>="19:00:00"& time1 <="23:59:59"]
  night=rbind(am,pm)
  night=night[order(maid, utc_timestamp),]
  
  #Cleaning and sorting data
  nightfilter=night[accuracy<=1000 & accuracy>=0]
  nightfilter$ID=seq.int(nrow(nightfilter))
  nightfilter=nightfilter[order(maid, utc_timestamp),]
  
  #lat long conversion to utm
  longlat2utm=function (x,y,ID,zone){
    xy=data.frame(ID = ID, X=x, Y=y)
    coordinates(xy)=c("X","Y")
    proj4string(xy)=CRS("+proj=longlat +datum=WGS84")
    res = spTransform(xy, CRS(paste("+proj=utm +zone=",zone," ellps=WGS84",sep='')))
    return(as.data.table(res))
  }
  
  nightfilter$utmz=(floor((nightfilter$lon + 180)/6) %% 60) + 1
  
  X=longlat2utm(nightfilter$lon,nightfilter$lat, ID=nightfilter$ID,zone=nightfilter$utmz)
  
  nightfilter=merge(nightfilter,X,by="ID")
  
  #indexing
  device_start_id=which(!duplicated(nightfilter$maid))
  device_end_id=which(!duplicated(nightfilter$maid,fromLast = TRUE))
  device_ind_array=cbind(device_start_id,device_end_id)
  
  #home identification function
  home_identification=function(trip_index,file){
    tmp_df=file[trip_index[1]:trip_index[2],]
    tmp_df=as.data.table(tmp_df)
    npoint=nrow(tmp_df)
    userid=tmp_df$maid[1]
    b=tmp_df[,c("X","Y")]
    c=dbscan(b,eps=100,minPts = 3)
    no_cluster=length(unique(c$cluster))
    tmp_df$cluster=c$cluster
    if(no_cluster>=2){
      home=tmp_df[cluster==names(sort(table(tmp_df[cluster!=0]$cluster),decreasing = TRUE)[1])]
      cluster_no=names(sort(table(tmp_df[cluster!=0]$cluster),decreasing = TRUE)[1])      
      cluster_row=nrow(tmp_df[cluster==names(sort(table(tmp_df[cluster!=0]$cluster),decreasing = TRUE)[1])])
      home_lat=median(home$lat)
      home_lon=median(home$lon)
      home_radius=max(c(distGeo(home[1:(nrow(home)),c("lon","lat")],c(home_lon,home_lat)),0))
    }
    else{
      cluster_no=0
      home_lat=0
      home_lon=0
      home_radius=0
      cluster_row=0
    }
    attr_vec=c(npoint,userid,no_cluster,home_lat,home_lon,home_radius,cluster_no,cluster_row)
    attr_vec
  }
  home_file=as.data.frame(t(apply(device_ind_array, 1, home_identification,file=nightfilter)))
  colnames(home_file)=c("npoint","maid","no_cluster","home_lat","home_lon","home_radius","cluster_no","cluster_rows")
  home_file=as.data.table(home_file)
  home_file=home_file[home_lat!=0]
  fwrite(home_file,paste0("/home/rstudio/provider/Data products/0614_0620/home location/home_location_100_3_7pm7am_device",j,".csv"))
  
}


#Run home location in paralel
start=Sys.time()
for (loop_id in 0:499){
  
  cl = makeCluster(2)
  registerDoSNOW(cl)
  getDoParWorkers()
  print(loop_id)
  
  foreach(core=((loop_id*2):((loop_id+1)*2-1)),.packages = c('data.table','rgdal','sp','dbscan','geosphere','lutz','lubridate'))%dopar%{
    home_location_identification(core)
  }
  stopCluster(cl)
  rm(cl)
  closeAllConnections()
  gc()
}
end=Sys.time()
end-start


#Read all CSV files and combine them

mypath ="/home/rstudio/provider/Data products/0614_0620/home location"
zipF <- list.files(path = mypath,pattern = "_3_7pm7am_device", full.names = TRUE)
home_location=data.table()
for (i in 1:1000){
  print(i)
  data=fread(zipF[i])
  home_location=rbind(home_location,data)
}
fwrite(home_location,"/home/rstudio/provider/Data products/0614_0620/home location/home_location_100_3_7pm7am.csv")

#get access to the s3 bucket containing raw data
Sys.setenv("AWS_ACCESS_KEY_ID" = "",
           "AWS_SECRET_ACCESS_KEY" = "")

#upload home loaction to s3 bucket

s3sync(
  path = "/home/rstudio/provider/Data products/0614_0620/home location/",
  'xx',
  prefix ="home_location_100_3_7pm7am.csv",
  direction = "upload",
  verbose = TRUE,
  create = FALSE,
)

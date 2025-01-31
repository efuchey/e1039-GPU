#include "reconstruction_helper.cuh"

// kernel functions: 
// CUDA C++ extends C++ by allowing the programmer to define C++ functions, called kernels, that, when called, 
// are executed N times in parallel by N different CUDA threads, as opposed to only once like regular C++ functions. 

//called over 8192 blocks 8 threads each
__global__ void gkernel_eR(gEventHitCollections* hitcolls, bool* hastoomanyhits) {
	//const int index = threadIdx.x + blockIdx.x * blockDim.x;
	assert(blockIdx.x>=0 && blockIdx.x<EstnEvtMax);
	
	__shared__ unsigned short station_multiplicity[THREADS_PER_BLOCK][5];//0: D0; 1: D2; 2: D3p; 3: D3m; 4: proptubes
	
	for(int i = 0; i<5; i++)station_multiplicity[threadIdx.x][i] = 0;
	
	float hitarraycopy[600];
	int nvalues;
	
	short hitflag[200];
	int nhits, hitidx;
	//const int //thread: threadIdx.x;
	//Load the hit collections: 3 wire chamber planes, 2 hodoscope planes, and 1 prop planes.
	// calculate the collection offsets:
	//
	const unsigned int detid_chambers[3] = {
		globalconsts::eff_detid_chambers[threadIdx.x],
		globalconsts::eff_detid_chambers[threadIdx.x+8],
		globalconsts::eff_detid_chambers[threadIdx.x+16]
	};
	const unsigned int nhits_chambers[3] = {
		hitcolls->NHitsChambers[blockIdx.x*nChamberPlanes+detid_chambers[0]-1], 
		hitcolls->NHitsChambers[blockIdx.x*nChamberPlanes+detid_chambers[1]-1], 
		hitcolls->NHitsChambers[blockIdx.x*nChamberPlanes+detid_chambers[2]-1] 
	};
	const unsigned int offsets_hitcoll_chambers[3] = {
		blockIdx.x*datasizes::eventhitsize[0]+datasizes::NHitsParam*datasizes::NMaxHitsChambers*(detid_chambers[0]-1), 
		blockIdx.x*datasizes::eventhitsize[0]+datasizes::NHitsParam*datasizes::NMaxHitsChambers*(detid_chambers[1]-1),
		blockIdx.x*datasizes::eventhitsize[0]+datasizes::NHitsParam*datasizes::NMaxHitsChambers*(detid_chambers[2]-1)
	};
	
	const unsigned int detid_hodo[2] = {
		31+threadIdx.x,
		31+threadIdx.x+8
	};
	
	const unsigned int nhits_hodo[2] = {
		hitcolls->NHitsHodo[blockIdx.x*nHodoPlanes+threadIdx.x], 
		hitcolls->NHitsHodo[blockIdx.x*nHodoPlanes+(threadIdx.x+8)]
	};
	const unsigned int offsets_hitcoll_hodo[2] = {
		blockIdx.x*datasizes::eventhitsize[1]+datasizes::NHitsParam*datasizes::NMaxHitsHodoscopes*threadIdx.x, 
		blockIdx.x*datasizes::eventhitsize[1]+datasizes::NHitsParam*datasizes::NMaxHitsHodoscopes*(threadIdx.x+8)
	};
	
	const unsigned int detid_prop = 47+threadIdx.x;
	const unsigned int nhits_prop = hitcolls->NHitsPropTubes[blockIdx.x*nPropPlanes+threadIdx.x];
	const unsigned int offset_hitcoll_prop = blockIdx.x*datasizes::eventhitsize[2]+datasizes::NHitsParam*datasizes::NMaxHitsPropTubes*threadIdx.x;
	
	const gHits hitcoll_prop(hitcolls->HitsPropTubesRawData, nhits_prop, offset_hitcoll_prop);
	nhits = event_reduction(hitcoll_prop, hitflag, detid_prop, nhits_prop);
	
	hitcolls->NHitsPropTubes[blockIdx.x*nPropPlanes+threadIdx.x] = nhits;
	hitidx = 0;
	for(int k = 0; k<nhits_prop; k++){
		if(hitflag[k]>0){
			hitarraycopy[hitidx] = hitcoll_prop.chan(k);
			hitarraycopy[hitidx+nhits] = hitcoll_prop.pos(k);
			hitarraycopy[hitidx+nhits*2] = hitcoll_prop.tdc(k);
			hitarraycopy[hitidx+nhits*3] = hitcoll_prop.flag(k);
			hitarraycopy[hitidx+nhits*4] = hitcoll_prop.drift(k);
			hitidx++;
		}
	}
	nvalues = datasizes::NHitsParam*nhits;
	for(int k = 0; k<nvalues; k++)hitcolls->HitsPropTubesRawData[offset_hitcoll_prop+k] = hitarraycopy[k];
	
	station_multiplicity[threadIdx.x][4]+= nhits;
			
	int stid;
	for(int i = 0; i<3; i++){
		if(detid_chambers[i]<=12){
			stid = 0;
		}else{
			stid = (detid_chambers[i]-7)/6;
		}
		gHits hitcoll_chambers = gHits(hitcolls->HitsChambersRawData, nhits_chambers[i], offsets_hitcoll_chambers[i]);
		nhits = event_reduction(hitcoll_chambers, hitflag, detid_chambers[i], nhits_chambers[i]);
		
		hitcolls->NHitsChambers[blockIdx.x*nChamberPlanes+detid_chambers[i]-1] = nhits;
		hitidx = 0;
		for(int k = 0; k<nhits_chambers[i]; k++){
			if(hitflag[k]>0){
				hitarraycopy[hitidx] = hitcoll_chambers.chan(k);
				hitarraycopy[hitidx+nhits] = hitcoll_chambers.pos(k);
				hitarraycopy[hitidx+nhits*2] = hitcoll_chambers.tdc(k);
				hitarraycopy[hitidx+nhits*3] = hitcoll_chambers.flag(k);
				hitarraycopy[hitidx+nhits*4] = hitcoll_chambers.drift(k);
				hitidx++;
			}
			//if(blockIdx.x==debug::EvRef)printf("thread %d detid %d chan %1.1f, drift %1.4f, flag %d, hitidx %d hitarray_chan %1.1f \n", threadIdx.x, detid_chambers[i], hitcoll_chambers.chan(k), hitcoll_chambers.drift(k), hitflag[k], hitidx-1, hitarraycopy[hitidx-1]);
		}
		nvalues = datasizes::NHitsParam*nhits;
		for(int k = 0; k<nvalues; k++)hitcolls->HitsChambersRawData[offsets_hitcoll_chambers[i]+k] = hitarraycopy[k];

		station_multiplicity[threadIdx.x][stid]+=nhits;
	}
	for(int i = 0; i<2; i++){
		gHits hitcoll_hodo = gHits(hitcolls->HitsHodoRawData, nhits_hodo[i], offsets_hitcoll_hodo[i]);
		nhits = event_reduction(hitcoll_hodo, hitflag, detid_hodo[i], nhits_hodo[i]);
		
		hitcolls->NHitsHodo[blockIdx.x*nHodoPlanes+detid_hodo[i]-31] = nhits;
		hitidx = 0;
		for(int k = 0; k<nhits_hodo[i]; k++){
			if(hitflag[k]>0){
				hitarraycopy[hitidx] = hitcoll_hodo.chan(k);
				hitarraycopy[hitidx+nhits] = hitcoll_hodo.pos(k);
				hitarraycopy[hitidx+nhits*2] = hitcoll_hodo.tdc(k);
				hitarraycopy[hitidx+nhits*3] = hitcoll_hodo.flag(k);
				hitarraycopy[hitidx+nhits*4] = hitcoll_hodo.drift(k);
				hitidx++;
			}
		}
		nvalues = datasizes::NHitsParam*nhits;
		for(int k = 0; k<nvalues; k++)hitcolls->HitsHodoRawData[offsets_hitcoll_hodo[i]+k] = hitarraycopy[k];
	}
	__syncthreads();
	
	unsigned short station_mult[5] = {0, 0, 0, 0, 0};
	for(short j = 0; j<5; j++){
		for(short i = 0; i<THREADS_PER_BLOCK; i++){
			station_mult[j]+= station_multiplicity[i][j];
		}
	}
	
	hastoomanyhits[blockIdx.x] = false;
	if(station_mult[0]>selection::MaxD0Multiplicity)hastoomanyhits[blockIdx.x] = true;
	if(station_mult[1]>selection::MaxD2Multiplicity)hastoomanyhits[blockIdx.x] = true;
	if(station_mult[2]>selection::MaxD3Multiplicity)hastoomanyhits[blockIdx.x] = true;
	if(station_mult[3]>selection::MaxD3Multiplicity)hastoomanyhits[blockIdx.x] = true;
	//if(station_mult[4]>selection::MaxPropMultiplicity)hastoomanyhits[blockIdx.x] = true;
	
#ifdef DEBUG
	if(blockIdx.x==debug::EvRef){
		for(int k = 0; k<3; k++){
		int nhits_chambers_ = hitcolls->NHitsChambers[blockIdx.x*nChamberPlanes+detid_chambers[k]-1];
		gHits hitcoll_chambers = gHits(hitcolls->HitsChambersRawData, nhits_chambers_, offsets_hitcoll_chambers[k]);
		printf(" det offset %d array offset %d nhits_chambers(%d) = %d \n", blockIdx.x*nChamberPlanes+detid_chambers[k]-1, offsets_hitcoll_chambers[k], detid_chambers[k], nhits_chambers_);
		for(int i = 0; i<nhits_chambers_; i++){
			printf("%d %d %1.0f %1.4f %1.4f %1.0f %1.4f\n", offsets_hitcoll_chambers[k], detid_chambers[k], hitcoll_chambers.chan(i), hitcoll_chambers.pos(i), hitcoll_chambers.tdc(i), hitcoll_chambers.flag(i), hitcoll_chambers.drift(i));
			//printf("%d %d %d %d %d %d %d %d %d %1.0f %1.4f\n", ev, offsets_hitcoll_chambers[k], detid_chambers[k], i, offsets_hitcoll_chambers[k]+i, offsets_hitcoll_chambers[k]+i+nhits_chambers[k], offsets_hitcoll_chambers[k]+i+nhits_chambers[k]*2, offsets_hitcoll_chambers[k]+i+nhits_chambers*3, offsets_hitcoll_chambers[k]+i+nhits_chambers[k]*4, hitcolls->HitsChambersRawData[offsets_hitcoll_chambers[k]+i], hitcolls->HitsChambersRawData[offsets_hitcoll_chambers[k]+i+nhits_chambers[2]]);
		}
		}
		int nhits_hodo_ = hitcolls->NHitsHodo[blockIdx.x*nHodoPlanes+threadIdx.x];
		gHits hitcoll_hodo = gHits(hitcolls->HitsHodoRawData, nhits_hodo_, offsets_hitcoll_hodo[0]);
		printf(" det offset %d array offset %d nhits_hodo(%d) = %d \n", blockIdx.x*nHodoPlanes+threadIdx.x, offsets_hitcoll_hodo[0], detid_hodo[0], nhits_hodo_);
		for(int i = 0; i<nhits_hodo_; i++){
			printf("%d %d %1.0f %1.4f %1.4f %1.0f %1.4f\n", offsets_hitcoll_hodo[0], 31+threadIdx.x, hitcoll_hodo.chan(i), hitcoll_hodo.pos(i), hitcoll_hodo.tdc(i), hitcoll_hodo.flag(i), hitcoll_hodo.drift(i));
			//printf("%d %d %d %d %d %d %d %d %d %1.0f %1.4f\n", ev, offsets_hitcoll_hodo[0], 31+threadIdx.x, i, offsets_hitcoll_hodo[0]+i, offsets_hitcoll_hodo[0]+i+nhits_hodo[0], offsets_hitcoll_hodo[0]+i+nhits_hodo[0]*2, offsets_hitcoll_hodo[0]+i+nhits_hodo[0]*3, offsets_hitcoll_hodo[0]+i+nhits_hodo[0]*4, hitcolls->HitsHodoRawData[offsets_hitcoll_hodo[0]+i], hitcolls->HitsHodoRawData[offsets_hitcoll_hodo[0]+i+nhits_hodo[0]]);

		}
		int nhits_prop_ = hitcolls->NHitsPropTubes[blockIdx.x*nPropPlanes+threadIdx.x];
		gHits hitcoll_prop2(hitcolls->HitsPropTubesRawData, nhits_prop_, offset_hitcoll_prop);
		printf(" det offset %d array offset %d nhits_prop(%d) = %d \n", blockIdx.x*nPropPlanes+threadIdx.x, offset_hitcoll_prop, 47+threadIdx.x, nhits_prop_);
		for(int i = 0; i<nhits_prop_; i++){
			printf("%d %d %1.0f %1.4f %1.4f %1.0f %1.4f\n", offset_hitcoll_prop, 47+threadIdx.x, hitcoll_prop2.chan(i), hitcoll_prop2.pos(i), hitcoll_prop2.tdc(i), hitcoll_prop2.flag(i), hitcoll_prop2.drift(i));
			//printf("%d %d %d %d %d %d %d %d %d %1.0f %1.4f\n", ev, offset_hitcoll_prop, 47+threadIdx.x, i, offset_hitcoll_prop+i, offset_hitcoll_prop+i+nhits_prop, offset_hitcoll_prop+i+nhits_prop*2, offset_hitcoll_prop+i+nhits_prop*3, offset_hitcoll_prop+i+nhits_prop*4, hitcolls->HitsPropTubesRawData[offset_hitcoll_prop+i], hitcolls->HitsPropTubesRawData[offset_hitcoll_prop+i+nhits_prop]);

		}
		if(threadIdx.x==0)for(int i = 0; i<5; i++)printf("thread %d station %d mult %d \n ", threadIdx.x, i, station_mult[i]);
	}
#endif
}



////////////////////////////////////
//
//          XZ TRACKING
//
////////////////////////////////////

__global__ void gKernel_XZ_tracking(
	gEventHitCollections* hitcolls,
	gEventTrackCollection* tklcoll,
	//const float* z_array,
	//const float* res_array,
	const gPlane* planes,
	int* nTracklets,
#ifdef DEBUG
	   const int* eventID,
#endif
	bool* hastoomanyhits)
//(gTrackingXZparams* parameters)			
{
	if(hastoomanyhits[blockIdx.x]){
#ifdef DEBUG
		if(threadIdx.x==0)printf("Evt %d discarded, too many hits\n", eventID[blockIdx.x]);
#endif
		return;
	}
	
	const int nbins_st2 = 7;//28/4
	//const int nbins_st3 = 28;//58/2
	//const int nbins_st3 = 14;
	const int nbins_st3 = 7;
	
	// 8 threads...
	// thread 0: bin0_st2 = 0/2*7, st3 = 3; thread 1: bin0_st2 = (1/2 = 0)*7, st3 = 1; thread 2: bin0_st2 = 2/2*7, st3 = 3; thread 3: bin0_st2 = (3/2 = 1)*7, st3 = 4; ...
	// const int bin0_st2 = (threadIdx.x/2)*nbins_st2;
	// const int bin0_st3 = 0;
	// 16 threads
	// const int bin0_st2 = (threadIdx.x/4)*nbins_st2;
	// const int bin0_st3 = (threadIdx.x%4/2)*nbins_st3;
	// 32 threads
	// thread 0: bin0_st2 = 0/8*7 = 0, st3 = 3; bin0_st3 = (0%8/2 = 0)*7 = 0; thread 1: bin0_st2 = (1/8 = 0)*7 = 0, st3 = 4, bin0_st3 = (1%8/2 = 0)*7 = 0; 
	// thread 2: bin0_st2 = 2/8*7 = 0, st3 = 3; bin0_st3 = (2%8/2 = 1)*7 = 7; thread 3: bin0_st2 = (3/8 = 0)*7 = 0, st3 = 4; bin0_st3 = (3%8/2 = 1)*7 = 7; 
	const int bin0_st2 = (threadIdx.x/8)*nbins_st2;
	const int bin0_st3 = (threadIdx.x%8/2)*nbins_st3;
	const int st3 = 3+threadIdx.x%2;//check d3p for even threads, d3m for odd threads...
	
#ifdef DEBUG
	if(blockIdx.x==debug::EvRef)printf(" XZ: thread %d bin0 st2 %d bin0 st3 %d \n", threadIdx.x, bin0_st2, bin0_st3);
#endif
	
	short hitflag1[100];
	short hitflag2[100];
	
	// As a starting point we will process 8 bins per thread: x acceptance divided by 4 * 2 bins for d3p and d3m 
	int nhitpairs_x2[nbins_st2];
	int nhitpairs_x3[nbins_st3];
        //pairs in station 2
        thrust::pair<int, int> hitpairs_x2[nbins_st2*globalconsts::MaxHitsProj_X];
        //pairs in station 3
        thrust::pair<int, int> hitpairs_x3[nbins_st3*globalconsts::MaxHitsProj_X];
	
	unsigned int offset_hitcoll;
	
	short stid, projid, detid, detoff;
	
	projid = 0;
	stid = 2;
	detoff = 1;
	short detid_list[4];
	
	//Get the required hit collections here!
	
	detid = globalconsts::detsuperid[stid][projid]*2;
	detid_list[0] = detid;
	int nhits_st2x;
	const gHits hits_st2x = hitcolls->hitschambers(blockIdx.x, detid, nhits_st2x);
	const float z_st2x = planes->z[detid];
	const float res_st2x = planes->resolution[detid];
	
	detid-= 1;
	detid_list[1] = detid;
	int nhits_st2xp;
	const gHits hits_st2xp = hitcolls->hitschambers(blockIdx.x, detid, nhits_st2xp);
	const float z_st2xp = planes->z[detid];
	const float res_st2xp = planes->resolution[detid];
	
	//stid = 2, projid = 0
	//make_hitpairs_in_station_bins(hits_st2x, nhits_st2x, hits_st2xp, nhits_st2xp, hitpairs_x2, nhitpairs_x2, bin0_st2, nbins_st2, hitflag1, hitflag2, stid, projid);
	make_hitpairs_in_station_bins(hits_st2x, nhits_st2x, hits_st2xp, nhits_st2xp, hitpairs_x2, nhitpairs_x2, bin0_st2, nbins_st2, hitflag1, hitflag2, stid);

	stid = st3;
	detid = globalconsts::detsuperid[stid][projid]*2;
	detid_list[2] = detid;
	int nhits_st3x;
	const gHits hits_st3x = hitcolls->hitschambers(blockIdx.x, detid, nhits_st3x);
#ifdef DEBUG	
	if(blockIdx.x==debug::EvRef && st3==4)printf("XZ: block %d detid %d nhits %d, vs %d \n", blockIdx.x, detid, nhits_st3x, hitcolls->NHitsChambers[blockIdx.x*nChamberPlanes+detid-1]);
#endif
	const float z_st3x = planes->z[detid];
	const float res_st3x = planes->resolution[detid];

	detid-= 1;
	int nhits_st3xp;
	detid_list[3] = detid;
	const gHits hits_st3xp = hitcolls->hitschambers(blockIdx.x, detid, nhits_st3xp);
#ifdef DEBUG	
	if(blockIdx.x==debug::EvRef && st3==4)printf("XZ: block %d detid %d nhits %d, vs %d \n", blockIdx.x, detid, nhits_st3xp, hitcolls->NHitsChambers[blockIdx.x*nChamberPlanes+detid-1]);
#endif
	const float z_st3xp = planes->z[detid];
	const float res_st3xp = planes->resolution[detid];
	
	//stid = 2, projid = 0
	//make_hitpairs_in_station_bins(hits_st3x, nhits_st3x, hits_st3xp, nhits_st3xp, hitpairs_x3, nhitpairs_x3, bin0_st3, nbins_st3, hitflag1, hitflag2, stid, projid);
	make_hitpairs_in_station_bins(hits_st3x, nhits_st3x, hits_st3xp, nhits_st3xp, hitpairs_x3, nhitpairs_x3, bin0_st3, nbins_st3, hitflag1, hitflag2, stid);
	
#ifdef DEBUG	
	if(blockIdx.x==debug::EvRef && st3==4){
		printf("XZ: nhits %d %d \n", nhits_st3x, nhits_st3xp);
		for(int i = 0; i<nbins_st3; i++){
			printf("XZ: thread %d npairs %d \n", threadIdx.x, nhitpairs_x3[i]);
			for(int j = 0; j<nhitpairs_x3[i]; j++){
				printf("XZ: thread %d < %d , %d >\n", threadIdx.x, hitpairs_x3[i+nbins_st3*j].first, hitpairs_x3[i+nbins_st3*j].second);
				if(hitpairs_x3[i+nbins_st3*j].first>=0)printf("XZ: thread %d bin %d st3x, hit %d chan %1.0f pos %1.4f \n", threadIdx.x, i, hitpairs_x3[i+nbins_st3*j].first, hits_st3x.chan(hitpairs_x3[i+nbins_st3*j].first), hits_st3x.pos(hitpairs_x3[i+nbins_st3*j].first));
				if(hitpairs_x3[i+nbins_st3*j].second>=0)printf("XZ: thread %d bin %d st3xp, hit %d chan %1.0f pos %1.4f \n", threadIdx.x, i, hitpairs_x3[i+nbins_st3*j].second, hits_st3xp.chan(hitpairs_x3[i+nbins_st3*j].second), hits_st3xp.pos(hitpairs_x3[i+nbins_st3*j].second) );
			}
		}
	}
	
	if(debug::EvRef==blockIdx.x)printf("XZ: thread %d dets %d %d %d %d \n", threadIdx.x, detid_list[0], detid_list[1], detid_list[2], detid_list[3]);
#endif
	
	stid = 6-1;
	detid = globalconsts::detsuperid[stid][projid]*2;
	int nhits_p1x1;
	const gHits hits_p1x1 = hitcolls->hitsprop(blockIdx.x, detid, nhits_p1x1);
	const float z_p1x1 = planes->z[detid];

	detid-= 1;
	int nhits_p1x2;
	const gHits hits_p1x2 = hitcolls->hitsprop(blockIdx.x, detid, nhits_p1x2);
	const float z_p1x2 = planes->z[detid];
	
	stid = 7-1;
	detid = globalconsts::detsuperid[stid][projid]*2;
	int nhits_p2x1;
	const gHits hits_p2x1 = hitcolls->hitsprop(blockIdx.x, detid, nhits_p2x1);
	const float z_p2x1 = planes->z[detid];

	detid-= 1;
	int nhits_p2x2;
	const gHits hits_p2x2 = hitcolls->hitsprop(blockIdx.x, detid, nhits_p2x2);
	const float z_p2x2 = planes->z[detid];

	// hodoscope hits
	stid = 1;//2-1
	detid = globalconsts::hodoplanesx[stid][0];
	int nhits_h2x1;
	const gHits hits_h2x1 = hitcolls->hitshodos(blockIdx.x, detid, nhits_h2x1);

	detid = globalconsts::hodoplanesx[stid][1];
	int nhits_h2x2;
	const gHits hits_h2x2 = hitcolls->hitshodos(blockIdx.x, detid, nhits_h2x2);
	
	stid = 2;//3-1
	detid = globalconsts::hodoplanesx[stid][0];
	int nhits_h3x1;
	const gHits hits_h3x1 = hitcolls->hitshodos(blockIdx.x, detid, nhits_h3x1);

	detid = globalconsts::hodoplanesx[stid][1];
	int nhits_h3x2;
	const gHits hits_h3x2 = hitcolls->hitshodos(blockIdx.x, detid, nhits_h3x2);

	stid = 3;//4-1
	detid = globalconsts::hodoplanesx[stid][0];
	int nhits_h4x1;
	const gHits hits_h4x1 = hitcolls->hitshodos(blockIdx.x, detid, nhits_h4x1);

	detid = globalconsts::hodoplanesx[stid][1];
	int nhits_h4x2;
	const gHits hits_h4x2 = hitcolls->hitshodos(blockIdx.x, detid, nhits_h4x2);

	bool maskhodo[4];


	bool bin_overflows = false;
	for(int bin = 0; bin<nbins_st2; bin++){
		if(nhitpairs_x2[bin]>globalconsts::MaxHitsProj_X)bin_overflows = true;
#ifdef DEBUG
		if(nhitpairs_x2[bin])printf("evt %d bin %d nhits x2 = %d\n", eventID[blockIdx.x], bin, nhitpairs_x2[bin]);
#endif
	}
	for(int bin = 0; bin<nbins_st3; bin++){
		if(nhitpairs_x3[bin]>globalconsts::MaxHitsProj_X)bin_overflows = true;
#ifdef DEBUG
		if(nhitpairs_x3[bin])printf("evt %d bin %d nhits x3 = %d\n", eventID[blockIdx.x], bin, nhitpairs_x3[bin]);
#endif
	}
	if(bin_overflows){
		hastoomanyhits[blockIdx.x] = true;
		return;
	}
	
	//variables for 2D track fit
	short detID[4];
	float X[4];
	float errX[4];
	float Z[4];
	
	float A_[4];
	float Ainv_[4];
	float B_[2];
	float Par[2];
	float ParErr[2];
	float chi2;

	float x0, tx, errx0, errtx;
	
	//Arrays for other basic hit info
	short elID[4];
	float drift[4];
	float tdc[4];
	short sign[4];
	
	//small varaibles for prop tube matching
	short nprop;//, iprop, idet;
	float xExp, ipos;
	bool checknext;
	
	short nhits_x;
	short nhits_x2, nhits_x3;
	short i_x, i_x2, i_x3;
	int i_hit;
	
	// if parallel:
	// const short nbins_st3 = globalconsts::N_WCHitsBins[2];
	const short nbins_total = nbins_st2*nbins_st3;
	short bin2, bin3;
	int binId;
	
	int nx2, nx3;
	int ncomb_x;
		
	int n_goodxz;

	//tracklet container://limit the access to the large tracklet arrays.
	const unsigned int tkl_coll_offset = blockIdx.x*datasizes::TrackSizeMax*datasizes::NTracksParam;
	const unsigned int array_thread_offset = threadIdx.x*datasizes::TrackSizeMax*datasizes::NTracksParam/THREADS_PER_BLOCK;
	const unsigned int tklmult_idx = blockIdx.x*THREADS_PER_BLOCK+threadIdx.x;

	tklcoll->NTracks[tklmult_idx] = 0;

	__shared__ unsigned int list_of_threads[THREADS_PER_BLOCK];
	__shared__ unsigned int ntkl_per_thread[THREADS_PER_BLOCK];
	for(int k = 0; k<THREADS_PER_BLOCK; k++){
		ntkl_per_thread[k] = 0;
		list_of_threads[k] = 0;
	}
	__shared__ short thread_min[THREADS_PER_BLOCK];//thread with lowest number of tracks: each thread
	__shared__ bool addtrack[THREADS_PER_BLOCK];//flag to mark threads requesting to add a new track in another thread.
	__shared__ bool threadbusy[THREADS_PER_BLOCK];//flag to indicate a busy thread - which means we need to find a new one
	unsigned int ntkl_min;
	unsigned int array_offset;
	unsigned int nthreads_busy;
	unsigned int nslots_available;
	
	for(short i = 0; i<nbins_total; i++){
		bin2 = i%nbins_st2;
		bin3 = (i-bin2)/nbins_st2;
		binId = threadIdx.x+THREADS_PER_BLOCK*i;
		//printf("bin %d %d\n", bin2, bin3);
		// if parallel:
		// bin3+=nbins_st3*i_thread;

		nx2 = nhitpairs_x2[bin2];
		nx3 = nhitpairs_x3[bin3];

		addtrack[threadIdx.x] = false;
		threadbusy[threadIdx.x] = false;

		if(nx2 == 0 || nx3==0) continue;
#ifdef DEBUG
		if(blockIdx.x==debug::EvRef && st3==4)printf("XZ: bin %d %d, nx %d %d \n", bin2, bin3, nx2, nx3);
#endif		
		//for(int k = 0; k<THREADS_PER_BLOCK; k++)ntkl_per_bin[k][i] = 0;

		// evaluating the number of combinations;
		ncomb_x = nx2*nx3;
		
		n_goodxz = 0;
		
		for(i_x = 0; i_x<ncomb_x; i_x++){
			i_x2 = i_x%nx2;
			i_x3 = (i_x-i_x2)/nx2;
			
			for(int k = 0; k<THREADS_PER_BLOCK; k++){
				list_of_threads[k] = 0;
				addtrack[k] = false;
				threadbusy[k] = false;
			}
			//addtrack[threadIdx.x] = false;
			//threadbusy[threadIdx.x] = false;
			
			nhits_x = 0;
			
			if(hitpairs_x2[bin2+nbins_st2*i_x2].first>=0){
				detID[nhits_x] = detid_list[0];
				i_hit = hitpairs_x2[bin2+nbins_st2*i_x2].first;
				//X[nhits_x] = hits_st2x.pos(i_hit);
				errX[nhits_x] = res_st2x;
				//Z[nhits_x] = z_st2x;
				elID[nhits_x] = (short)hits_st2x.chan(i_hit);
				tdc[nhits_x] = hits_st2x.tdc(i_hit);
				drift[nhits_x] = hits_st2x.drift(i_hit);
				sign[nhits_x] = 0;
				calculate_xz_fy(detID[nhits_x], elID[nhits_x], drift[nhits_x], sign[nhits_x], 0, 0, planes, X[nhits_x], Z[nhits_x]);
#ifdef DEBUG
				if(blockIdx.x==debug::EvRef)printf(" true x %1.4f z %1.4f simple x %1.4f z %1.4f \n", X[nhits_x], Z[nhits_x], hits_st2x.pos(i_hit), z_st2x);
#endif
				nhits_x++;
			}
			if(hitpairs_x2[bin2+nbins_st2*i_x2].second>=0){
				detID[nhits_x] = detid_list[1];
				i_hit = hitpairs_x2[bin2+nbins_st2*i_x2].second;
				//X[nhits_x] = hits_st2xp.pos(i_hit);
				errX[nhits_x] = res_st2xp;
				//Z[nhits_x] = z_st2xp;
				elID[nhits_x] = (short)hits_st2xp.chan(i_hit);
				tdc[nhits_x] = hits_st2xp.tdc(i_hit);
				drift[nhits_x] = hits_st2xp.drift(i_hit);
				sign[nhits_x] = 0;
				calculate_xz_fy(detID[nhits_x], elID[nhits_x], drift[nhits_x], sign[nhits_x], 0, 0, planes, X[nhits_x], Z[nhits_x]);
				nhits_x++;
			}
			
			nhits_x2 = nhits_x;
			if(nhits_x2==0) continue;

#ifdef DEBUG
			if(blockIdx.x==debug::EvRef && st3==4) printf("XZ: thread %d in loop (i_x2 %d i_x3 %d): < %d , %d >\n", threadIdx.x, i_x2, i_x3, hitpairs_x3[bin3+nbins_st3*i_x3].first, hitpairs_x3[bin3+nbins_st3*i_x3].second);
#endif
			
			if(hitpairs_x3[bin3+nbins_st3*i_x3].first>=0){
				detID[nhits_x] = detid_list[2];
				i_hit = hitpairs_x3[bin3+nbins_st3*i_x3].first;
				//X[nhits_x] = hits_st3x.pos(i_hit);
				errX[nhits_x] = res_st3x;
				//Z[nhits_x] = z_st3x;
				elID[nhits_x] = (short)hits_st3x.chan(i_hit);
				tdc[nhits_x] = hits_st3x.tdc(i_hit);
				drift[nhits_x] = hits_st3x.drift(i_hit);
				sign[nhits_x] = 0;
				calculate_xz_fy(detID[nhits_x], elID[nhits_x], drift[nhits_x], sign[nhits_x], 0, 0, planes, X[nhits_x], Z[nhits_x]);
				nhits_x++;
			}
			if(hitpairs_x3[bin3+nbins_st3*i_x3].second>=0){
				detID[nhits_x] = detid_list[3];
				i_hit = hitpairs_x3[bin3+nbins_st3*i_x3].second;
				//X[nhits_x] = hits_st3xp.pos(i_hit);
				errX[nhits_x] = res_st3xp;
				//Z[nhits_x] = z_st3xp;
				elID[nhits_x] = (short)hits_st3xp.chan(i_hit);
				tdc[nhits_x] = hits_st3xp.tdc(i_hit);
				drift[nhits_x] = hits_st3xp.drift(i_hit);
				sign[nhits_x] = 0;
				calculate_xz_fy(detID[nhits_x], elID[nhits_x], drift[nhits_x], sign[nhits_x], 0, 0, planes, X[nhits_x], Z[nhits_x]);
				nhits_x++;
			}
			
			nhits_x3 = nhits_x-nhits_x2;
			if(nhits_x3==0) continue;

			
			fit_2D_track(nhits_x, X, Z, errX, A_, Ainv_, B_, Par, ParErr, chi2);
			x0 = Par[0];
			tx = Par[1];
			errx0 = ParErr[0];
			errtx = ParErr[1];

			if(fabs(x0)>X0_MAX+2*errx0 || fabs(tx)>TX_MAX+2*errtx)continue;
			
			resolve_leftright_xhits(x0, tx, errx0, errtx, nhits_x, detID, X, drift, sign, planes->z, 150.);
			resolve_single_leftright_xhits(x0, tx, nhits_x, detID, X, sign, planes->z);
			
			fit_2D_track_drift(nhits_x, X, drift, sign, Z, errX, A_, Ainv_, B_, Par, ParErr, chi2);
			x0 = Par[0];
			tx = Par[1];
			errx0 = ParErr[0];
			errtx = ParErr[1];

			if(fabs(x0)>X0_MAX || fabs(tx)>TX_MAX)continue;
			//if(fabs(x0+tx*globalconsts::Z_KMAG_BEND)>globalconsts::X_KMAG_BEND)continue;
			//the following does not figure in the ktracker selection... yet it is fairly effective
			//if(fabs(x0)<10.0)continue;
			//if(x0<0 && tx<-x0*0.0008)continue;
			//if(x0>0 && tx>-x0*0.0008)continue;

			
#ifdef DEBUG
			if(blockIdx.x==debug::EvRef)printf("XZ: evt %d x0 = %1.4f, tx = %1.4f \n", blockIdx.x, x0, tx);
#endif
			n_goodxz++;
			
			//prop matching
			nprop = 0;
			checknext = true;

			//we want at least one hit in p1x1 or p1x2...
			for(int n = 0; n<nhits_p1x1; n++){
				ipos = hits_p1x1.pos(n);
				xExp = tx*z_p1x1+x0;
#ifdef DEBUG
				if(blockIdx.x==debug::EvRef)printf("XZ: evt %d p1x1, ipos = %1.4f, xExp = %1.4f, diff = %1.4f \n", blockIdx.x, ipos, xExp, ipos-xExp);
#endif
				if(fabs(ipos-xExp)<5.08f){
					nprop++;
					checknext = false;
					break;
				}
			}
			if(checknext){
				for(int n = 0; n<nhits_p1x2; n++){
					ipos = hits_p1x2.pos(n);
					xExp = tx*z_p1x2+x0;
#ifdef DEBUG
					if(blockIdx.x<=debug::EvRef)printf("XZ: evt %d p1x2, ipos = %1.4f, xExp = %1.4f, diff = %1.4f \n", blockIdx.x, ipos, xExp, ipos-xExp);
#endif
					if(fabs(ipos-xExp)<5.08f){
						nprop++;
//						checknext = false;
						break;
					}
				}
			}
			//and at least one hit in p2x1 or p2x2
			checknext = true;
			
			if(checknext){
				for(int n = 0; n<nhits_p2x1; n++){
					ipos = hits_p2x1.pos(n);
					xExp = tx*z_p2x1+x0;
#ifdef DEBUG
					if(blockIdx.x<=debug::EvRef)printf("XZ: evt %d p2x1, ipos = %1.4f, xExp = %1.4f, diff = %1.4f \n", blockIdx.x, ipos, xExp, ipos-xExp);
#endif
					if(fabs(ipos-xExp)<7.62f){
						nprop++;
						checknext = false;
						break;
					}
				}
			}
			if(checknext){
				for(int n = 0; n<nhits_p2x2; n++){
					ipos = hits_p2x2.pos(n);
					xExp = tx*z_p2x2+x0;
#ifdef DEBUG
					if(blockIdx.x<=debug::EvRef)printf("XZ: evt %d p2x2, ipos = %1.4f, xExp = %1.4f, diff = %1.4f \n", blockIdx.x, ipos, xExp, ipos-xExp);
#endif
					if(fabs(ipos-xExp)<7.62f){
						nprop++;
//						checknext = false;
						break;
					}
				}
			}
			//
			if(nprop<selection::NpropXYhitsMin)continue;
			
			//hodoscope
			stid = 1;//2-1

			maskhodo[stid] = 0;
			detid = globalconsts::hodoplanesx[stid][0];
			maskhodo[stid] = match_track_XZ_to_hodo(stid, detid, nhits_h2x1, hits_h2x1, x0, tx, errx0, errtx, planes->z);
			if(!maskhodo[stid]){
				detid = globalconsts::hodoplanesx[stid][1];
				maskhodo[stid] = maskhodo[stid] || match_track_XZ_to_hodo(stid, detid, nhits_h2x2, hits_h2x2, x0, tx, errx0, errtx, planes->z);
			}
			if(!maskhodo[stid])continue;
			
			stid = 2;//3-1
			maskhodo[stid] = 0;
			detid = globalconsts::hodoplanesx[stid][0];
			maskhodo[stid] = match_track_XZ_to_hodo(stid, detid, nhits_h3x1, hits_h3x1, x0, tx, errx0, errtx, planes->z);
			if(!maskhodo[stid]){
				detid = globalconsts::hodoplanesx[stid][1];
				maskhodo[stid] = maskhodo[stid] || match_track_XZ_to_hodo(stid, detid, nhits_h3x2, hits_h3x2, x0, tx, errx0, errtx, planes->z);
			}
			if(!maskhodo[stid])continue;

			stid = 3;//4-1
			maskhodo[stid] = 0;
			detid = globalconsts::hodoplanesx[stid][0];
			maskhodo[stid] = match_track_XZ_to_hodo(stid, detid, nhits_h4x1, hits_h4x1, x0, tx, errx0, errtx, planes->z);
			if(!maskhodo[stid]){
				detid = globalconsts::hodoplanesx[stid][1];
				maskhodo[stid] = maskhodo[stid] || match_track_XZ_to_hodo(stid, detid, nhits_h4x2, hits_h4x2, x0, tx, errx0, errtx, planes->z);
			}
			if(!maskhodo[stid])continue;
			
			//we can probably afford to spare time for synchronization here since XZ is extremely fast!
			addtrack[threadIdx.x] = true;

#ifdef DEBUG
			if(blockIdx.x==debug::EvRef)printf("XZ: thread %d wants to add a track!\n", threadIdx.x);
#endif
			ntkl_min = 100000;
			thread_min[threadIdx.x] = -1;
			nthreads_busy = 0;
			nslots_available = datasizes::TrackSizeMax;
			__syncthreads();
			for(int k = 0; k<THREADS_PER_BLOCK; k++){
				//list_of_threads[k] = 0;
				//looking for thread with least number of tracks (thread_min)
				//look only for threads with same "parity"
				if(ntkl_min>ntkl_per_thread[k] && st3==3+k%2){
					ntkl_min = ntkl_per_thread[k];
					thread_min[threadIdx.x] = k;
#ifdef DEBUG
					if(blockIdx.x==debug::EvRef)printf("XZ: k %d st3 %d 3+kmod2 %d ntkl_min %d ntkl_per_thread %d thread_min(%d) = %d \n", k, st3, 3+k%2, ntkl_min, ntkl_per_thread[k], threadIdx.x, thread_min[threadIdx.x]);
#endif
					//threadIdx.x*datasizes::TrackSizeMax*datasizes::NTracksParam/THREADS_PER_BLOCK;
				}
				nslots_available-= ntkl_per_thread[k];
				// here we have a first "pick" for alternate thread.
				// listing the threads which are "busy" with a "addtrack" request here.
				if(addtrack[k]){
					list_of_threads[nthreads_busy] = k;
					nthreads_busy++;
#ifdef DEBUG
					if(blockIdx.x==debug::EvRef)printf("XZ: thread? %d, nthreads_busy %d, list_of_threads = %d \n", k, nthreads_busy, list_of_threads[nthreads_busy-1]);
#endif
				}

			}
#ifdef DEBUG
			if(blockIdx.x==debug::EvRef)printf("XZ: thread_min(%d) = %d \n", threadIdx.x, thread_min[threadIdx.x]);
			
			if(blockIdx.x==debug::EvRef)if( thread_min[threadIdx.x]%2 != threadIdx.x%2 )printf("XZ: !!! thread_min(%d) = %d \n", threadIdx.x, thread_min[threadIdx.x]);
			if(blockIdx.x==debug::EvRef){
				printf("XZ: number of slots available %d\n", nslots_available);
				for(int m = 0; m<nthreads_busy; m++)printf("XZ:  m %d, list_of_threads[m] = %d \n", m, list_of_threads[m]);
			}
#endif
			//if the number of tracks to add is greater than the number of slots available, we stop - the event is too full. 
			if(nslots_available<nthreads_busy){
				printf("WARNING: Block %d cannot store anymore tracks! ending the event with a high multiplicity flag! \n", blockIdx.x);
				hastoomanyhits[blockIdx.x] = true;
				break;
			}
			__syncthreads();
#ifdef DEBUG
			if(blockIdx.x==debug::EvRef)printf("XZ: number of threads requesting to add a track (thread %d): %d  \n", threadIdx.x, nthreads_busy);
#endif
			//first, assign a unique "thread min" for each full thread so that they don't step on each other...
			// we have the following info:
			//   the list of threads that want to add a track in another thread,
			//   the number of tracks in each thread
			//   the "thread_min" i.e. the first alternate thread candidate for all threads. 
			threadbusy[thread_min[list_of_threads[0]]] = true;
			for(int l = 1; l<nthreads_busy; l++){
#ifdef DEBUG
				if(blockIdx.x==debug::EvRef)printf("XZ: (thread %d) list_of_threads %d thread_min %d thread_min[l] %d =? thread_min[l-1] %d \n", threadIdx.x, l, list_of_threads[l], thread_min[list_of_threads[l]], thread_min[list_of_threads[l-1]]);
#endif
				if(thread_min[list_of_threads[l]]==thread_min[list_of_threads[l-1]] || // if the current "alternate" thread is the same as the previous one 
					thread_min[list_of_threads[l]]==thread_min[list_of_threads[0]] || // or if it's the same as the first one
					st3!=3+thread_min[list_of_threads[l]]%2 ){ // or if the thread_min is not compatible with the actual thread 
					threadbusy[thread_min[list_of_threads[l]]] = true; // the thread is marked as busy and cannot be used
#ifdef DEBUG
					if(blockIdx.x==debug::EvRef)printf("XZ: (thread %d) thread %d busy\n", threadIdx.x, thread_min[list_of_threads[l]]);
#endif
				}
				
				//if the thread is busy, find another thread!
				if(threadbusy[thread_min[threadIdx.x]]){
					ntkl_min = 100000;
					for(int k = 0; k<THREADS_PER_BLOCK; k++){
						//we want another thread that is the least populated possible, that is not already busy, and that is compatible with the actual thread...
						if(ntkl_min>ntkl_per_thread[k] && !threadbusy[k] && thread_min[list_of_threads[l]]%2==k%2){ 
							ntkl_min = ntkl_per_thread[k];
							thread_min[list_of_threads[l]] = k;
							//thread_min[threadIdx.x] = k;
							threadbusy[k] = true;
#ifdef DEBUG
							if(blockIdx.x==debug::EvRef)printf("XZ: k %d ntkl_min %d list_of_threads %d thread_min(listofthreads[l]) = %d, thread_min(thread)\n", k, ntkl_min, list_of_threads[l], thread_min[list_of_threads[l]], thread_min[threadIdx.x]);
#endif
						}
					}
#ifdef DEBUG
					if(blockIdx.x==debug::EvRef)printf("XZ: thread %d ntkl_min %d thread_min(thread) = %d\n", threadIdx.x, ntkl_min, thread_min[threadIdx.x]);
#endif
				}
			}
			__syncthreads();
#ifdef DEBUG
			if(blockIdx.x==debug::EvRef)printf("XZ: alt thread chosen for thread %d: %d \n", threadIdx.x, thread_min[threadIdx.x]);
#endif
			array_offset = thread_min[threadIdx.x]*datasizes::TrackSizeMax*datasizes::NTracksParam/THREADS_PER_BLOCK;

#ifdef DEBUG
			if(blockIdx.x==debug::EvRef)printf("XZ: actual thread %d store thread %d offset %d stid %d local bin %d, bin0 st2 %d, bin0 st3 %d, st3 %d, ntkl_per_thread %d \n",  threadIdx.x, thread_min[threadIdx.x], tkl_coll_offset+array_offset, binId, i, bin0_st2, bin0_st3, st3, ntkl_per_thread[thread_min[threadIdx.x]]);

			if( threadIdx.x%2 != thread_min[threadIdx.x]%2 )printf("XZ:  !!! actual thread %d  store thread %d, st3 %d st_thread %d\n", threadIdx.x, thread_min[threadIdx.x], st3, 3+thread_min[threadIdx.x]%2);
			
			for(int kk = 0; kk<nthreads_busy; kk++){
				for(int ll = 0; ll<nthreads_busy; ll++){
					if(kk==ll)continue;
					if(thread_min[list_of_threads[kk]]==thread_min[list_of_threads[ll]] && ntkl_per_thread[list_of_threads[kk]]==ntkl_per_thread[list_of_threads[ll]]){
						printf("XZ: !!! alt thread chosen for thread %d: %d (n_tkl = %d) == alt thread chosen for thread %d: %d (n_tkl = %d) \n", list_of_threads[kk], thread_min[list_of_threads[kk]], ntkl_per_thread[list_of_threads[kk]], list_of_threads[ll], thread_min[list_of_threads[ll]], ntkl_per_thread[list_of_threads[ll]]);
					}
				}
			}
#endif
			
			tklcoll->setStationID(tkl_coll_offset+array_offset, ntkl_per_thread[thread_min[threadIdx.x]], (float)binId);
			tklcoll->setThreadID(tkl_coll_offset+array_offset, ntkl_per_thread[thread_min[threadIdx.x]], (float)threadIdx.x);
			tklcoll->setnHits(tkl_coll_offset+array_offset, ntkl_per_thread[thread_min[threadIdx.x]], (float)nhits_x);
			tklcoll->setTx(tkl_coll_offset+array_offset, ntkl_per_thread[thread_min[threadIdx.x]], tx);
			tklcoll->setX0(tkl_coll_offset+array_offset, ntkl_per_thread[thread_min[threadIdx.x]], x0);
			tklcoll->setErrTx(tkl_coll_offset+array_offset, ntkl_per_thread[thread_min[threadIdx.x]], errtx);
			tklcoll->setErrX0(tkl_coll_offset+array_offset, ntkl_per_thread[thread_min[threadIdx.x]], errx0);
			
			for(int n = 0; n<nhits_x; n++){
				tklcoll->setHitDetID(tkl_coll_offset+array_offset, ntkl_per_thread[thread_min[threadIdx.x]], n, detID[n]);
				tklcoll->setHitChan(tkl_coll_offset+array_offset, ntkl_per_thread[thread_min[threadIdx.x]], n, elID[n]);
				tklcoll->setHitPos(tkl_coll_offset+array_offset, ntkl_per_thread[thread_min[threadIdx.x]], n, X[n]);
				tklcoll->setHitDrift(tkl_coll_offset+array_offset, ntkl_per_thread[thread_min[threadIdx.x]], n, drift[n]);
				tklcoll->setHitSign(tkl_coll_offset+array_offset, ntkl_per_thread[thread_min[threadIdx.x]], n, sign[n]);
				tklcoll->setHitTDC(tkl_coll_offset+array_offset, ntkl_per_thread[thread_min[threadIdx.x]], n, tdc[n]);
				tklcoll->setHitResidual(tkl_coll_offset+array_offset, ntkl_per_thread[thread_min[threadIdx.x]], n, 0.0);
			}
			ntkl_per_thread[thread_min[threadIdx.x]]++;
			tklcoll->NTracks[blockIdx.x*THREADS_PER_BLOCK+thread_min[threadIdx.x]]++;
			__syncthreads();
		}// end loop on hits
	}//end loop on bins
	//evaluate number of tracklets

	__syncthreads();
	
	int N_tracklets = 0;

#ifdef DEBUG
	if(blockIdx.x==debug::EvRef)printf("XZ: block %d thread %d tracklets per thread: %d \n", blockIdx.x, threadIdx.x, ntkl_per_thread[threadIdx.x]);
#endif
	//__shared__ unsigned int array_thread_offset[THREADS_PER_BLOCK];
	for(int k = 0; k<THREADS_PER_BLOCK; k++){
		if(tklcoll->NTracks[tklmult_idx]!=ntkl_per_thread[threadIdx.x])printf("block %d, thread %d n tracks for thread ? %d %d \n", blockIdx.x, threadIdx.x, tklcoll->NTracks[tklmult_idx], ntkl_per_thread[threadIdx.x]);
		N_tracklets+= ntkl_per_thread[k];
	}
	if(ntkl_per_thread[threadIdx.x]>datasizes::TrackSizeMax/THREADS_PER_BLOCK){
#ifdef DEBUG
		printf("block %d thread %d tracklets per thread: %d \n", blockIdx.x, threadIdx.x, ntkl_per_thread[threadIdx.x]);
#endif
		hastoomanyhits[blockIdx.x] = true;
	}
	nTracklets[blockIdx.x] = N_tracklets;
#ifdef DEBUG
	if(blockIdx.x==debug::EvRef)printf("XZ: Ntracklets %d \n", N_tracklets);
#endif
	//at the end like that it's probably fine...
	if(N_tracklets>=datasizes::TrackSizeMax){
		printf("XZ: block %d thread %d tracklets total %d \n", blockIdx.x, threadIdx.x, N_tracklets);
		hastoomanyhits[blockIdx.x] = true;
		tklcoll->NTracks[blockIdx.x] = blockIdx.x*THREADS_PER_BLOCK+threadIdx.x;
	}
#ifdef DEBUG
	else{
		for(int m = 0; m<ntkl_per_thread[threadIdx.x]; m++){
			if(blockIdx.x==debug::EvRef)printf("XZ: thread: %d, m %d, offset %d stid/bin?  %1.0f thread %1.0f nhits %1.0f x0 %1.4f tx %1.4f \n", 
				threadIdx.x, m, tkl_coll_offset+array_thread_offset, 
				tklcoll->TracksRawData[tkl_coll_offset+array_thread_offset+m*datasizes::NTracksParam],  
				tklcoll->TracksRawData[tkl_coll_offset+array_thread_offset+m*datasizes::NTracksParam+1],  
				tklcoll->TracksRawData[tkl_coll_offset+array_thread_offset+m*datasizes::NTracksParam+2], 
				tklcoll->TracksRawData[tkl_coll_offset+array_thread_offset+m*datasizes::NTracksParam+7], 
				tklcoll->TracksRawData[tkl_coll_offset+array_thread_offset+m*datasizes::NTracksParam+5]
				);
		}
	}
#endif

}


////////////////////////////////////
//
//          YZ TRACKING
//
////////////////////////////////////

__global__ void gKernel_YZ_tracking(
	gEventHitCollections* hitcolls,
	gEventTrackCollection* tklcoll,
	const gPlane* planes,
#ifdef DEBUG
	int* eventID,
#endif
	bool* hastoomanyhits)
{
	if(hastoomanyhits[blockIdx.x]){
#ifdef DEBUG
		if(threadIdx.x==0)printf("YZ: Evt %d discarded, too many hits\n", eventID[blockIdx.x]);
#endif
		return;
	}
	const int nbins_st2 = 7;
	//const int nbins_st3 = 28;
	//const int nbins_st3 = 14;
	const int nbins_st3 = 7;
	
	const int st3 = 3+threadIdx.x%2;//check d3p for even threads, d3m for odd threads...
	
#ifdef DEBUG
	if(blockIdx.x==debug::EvRef)printf("YZ:  thread %d bin0 st2 %d bin0 st3 %d \n", threadIdx.x, bin0_st2, bin0_st3);
#endif

	short hitidx1[100];
	short hitidx2[100];
	short hitflag1[100];
	short hitflag2[100];
	
        //pairs in station 2
        thrust::pair<int, int> hitpairs_u2[100];
        //pairs in station 3
        thrust::pair<int, int> hitpairs_u3[100];

        //pairs in station 2
        thrust::pair<int, int> hitpairs_v2[100];
        //pairs in station 3
        thrust::pair<int, int> hitpairs_v3[100];
	
	
	unsigned int offset_hitcoll;
	
	short stid, projid, detid, detoff, chan;
	
	projid = 1;
	stid = 2;
	detoff = 1;
	short detid_list[8];
	float det_spacing[8];
	
	//Get the required hit collections here!
	
	detid = globalconsts::detsuperid[stid][projid]*2;
	detid_list[0] = detid;
	det_spacing[0] = planes->spacing[detid];
	int nhits_st2u;
	const gHits hits_st2u = hitcolls->hitschambers(blockIdx.x, detid, nhits_st2u);
	const float z_st2u = planes->z[detid];
	const float res_st2u = planes->resolution[detid];
	
	detid-= 1;
	detid_list[1] = detid;
	det_spacing[1] = planes->spacing[detid];
	int nhits_st2up;
	const gHits hits_st2up = hitcolls->hitschambers(blockIdx.x, detid, nhits_st2up);
	const float z_st2up = planes->z[detid];
	const float res_st2up = planes->resolution[detid];
	
	projid = 2;
	detid = globalconsts::detsuperid[stid][projid]*2;
	detid_list[2] = detid;
	det_spacing[2] = planes->spacing[detid];
	int nhits_st2v;
	const gHits hits_st2v = hitcolls->hitschambers(blockIdx.x, detid, nhits_st2v);
	const float z_st2v = planes->z[detid];
	const float res_st2v = planes->resolution[detid];
	
	detid-= 1;
	detid_list[3] = detid;
	det_spacing[3] = planes->spacing[detid];
	int nhits_st2vp;
	const gHits hits_st2vp = hitcolls->hitschambers(blockIdx.x, detid, nhits_st2vp);
	const float z_st2vp = planes->z[detid];
	const float res_st2vp = planes->resolution[detid];
		
	projid = 1;
	stid = st3;
	detid = globalconsts::detsuperid[stid][projid]*2;
	detid_list[4] = detid;
	det_spacing[4] = planes->spacing[detid];
	int nhits_st3u;
	const gHits hits_st3u = hitcolls->hitschambers(blockIdx.x, detid, nhits_st3u);
	const float z_st3u = planes->z[detid];
	const float res_st3u = planes->resolution[detid];

	detid-= 1;
	int nhits_st3up;
	detid_list[5] = detid;
	det_spacing[5] = planes->spacing[detid];
	const gHits hits_st3up = hitcolls->hitschambers(blockIdx.x, detid, nhits_st3up);
	const float z_st3up = planes->z[detid];
	const float res_st3up = planes->resolution[detid];
	
	projid = 2;
	detid = globalconsts::detsuperid[stid][projid]*2;
	detid_list[6] = detid;
	det_spacing[6] = planes->spacing[detid];
	int nhits_st3v;
	const gHits hits_st3v = hitcolls->hitschambers(blockIdx.x, detid, nhits_st3v);
	const float z_st3v = planes->z[detid];
	const float res_st3v = planes->resolution[detid];
	
	detid-= 1;
	int nhits_st3vp;
	detid_list[7] = detid;
	det_spacing[7] = planes->spacing[detid];
	const gHits hits_st3vp = hitcolls->hitschambers(blockIdx.x, detid, nhits_st3vp);
	const float z_st3vp = planes->z[detid];
	const float res_st3vp = planes->resolution[detid];

#ifdef PROP_Y_MATCH	
	int nprop;
	float yExp, ipos;
	bool checknext;

	// proportional tube hits
	projid = 1;
	stid = 6-1;
	detid = globalconsts::detsuperid[stid][projid]*2;
	int nhits_p1y1;
	const gHits hits_p1y1 = hitcolls->hitsprop(blockIdx.x, detid, nhits_p1y1);
	const float z_p1y1 = planes->z[detid];

	detid-= 1;
	int nhits_p1y2;
	const gHits hits_p1y2 = hitcolls->hitsprop(blockIdx.x, detid, nhits_p1y2);
	const float z_p1y2 = planes->z[detid];
	
	stid = 7-1;
	detid = globalconsts::detsuperid[stid][projid]*2;
	int nhits_p2y1;
	const gHits hits_p2y1 = hitcolls->hitsprop(blockIdx.x, detid, nhits_p2y1);
	const float z_p2y1 = planes->z[detid];

	detid-= 1;
	int nhits_p2y2;
	const gHits hits_p2y2 = hitcolls->hitsprop(blockIdx.x, detid, nhits_p2y2);
	const float z_p2y2 = planes->z[detid];
#endif
	
	// hodoscope hits
	stid = 1;//2-1
	detid = globalconsts::hodoplanesx[stid][0];
	int nhits_h2x1;
	const gHits hits_h2x1 = hitcolls->hitshodos(blockIdx.x, detid, nhits_h2x1);
#ifdef DEBUG
	if(blockIdx.x==debug::EvRef && threadIdx.x==0){printf("YZ: nhits h2x1 %d \n", nhits_h2x1);
	for(int l = 0; l<nhits_h2x1; l++)printf("YZ: det %d chan %1.0f pos %1.4f \n", detid, hits_h2x1.chan(l), hits_h2x1.pos(l));
	}
#endif


	detid = globalconsts::hodoplanesx[stid][1];
	int nhits_h2x2;
	const gHits hits_h2x2 = hitcolls->hitshodos(blockIdx.x, detid, nhits_h2x2);
#ifdef DEBUG
	if(blockIdx.x==debug::EvRef && threadIdx.x==0){printf("YZ: nhits h2x2 %d \n", nhits_h2x2);
	for(int l = 0; l<nhits_h2x2; l++)printf("YZ: det %d chan %1.0f pos %1.4f \n", detid, hits_h2x2.chan(l), hits_h2x2.pos(l));
	}
#endif

#ifdef HODO_Y_MATCH
	detid = globalconsts::hodoplanesy[stid][0];
	int nhits_h2y1;
	const gHits hits_h2y1 = hitcolls->hitshodos(blockIdx.x, detid, nhits_h2y1);
#ifdef DEBUG
	if(blockIdx.x==debug::EvRef && threadIdx.x==0){printf("YZ: nhits h2y1 %d \n", nhits_h2y1);
	for(int l = 0; l<nhits_h2y1; l++)printf("YZ: det %d chan %1.0f pos %1.4f \n", detid, hits_h2y1.chan(l), hits_h2y1.pos(l));
	}
#endif

	detid = globalconsts::hodoplanesy[stid][1];
	int nhits_h2y2;
	const gHits hits_h2y2 = hitcolls->hitshodos(blockIdx.x, detid, nhits_h2y2);
#ifdef DEBUG
	if(blockIdx.x==debug::EvRef && threadIdx.x==0){printf("YZ: nhits h2y2 %d \n", nhits_h2y2);
	for(int l = 0; l<nhits_h2y2; l++)printf("YZ: det %d chan %1.0f pos %1.4f \n", detid, hits_h2y2.chan(l), hits_h2y2.pos(l));
	}
#endif
#endif
	
	stid = 2;//3-1
	detid = globalconsts::hodoplanesx[stid][0];
	int nhits_h3x1;
	const gHits hits_h3x1 = hitcolls->hitshodos(blockIdx.x, detid, nhits_h3x1);
#ifdef DEBUG
	if(blockIdx.x==debug::EvRef && threadIdx.x==0){printf("YZ: nhits h3x1 %d \n", nhits_h3x1);
	for(int l = 0; l<nhits_h3x1; l++)printf("YZ: det %d chan %1.0f pos %1.4f \n", detid, hits_h3x1.chan(l), hits_h3x1.pos(l));
	}
#endif

	detid = globalconsts::hodoplanesx[stid][1];
	int nhits_h3x2;
	const gHits hits_h3x2 = hitcolls->hitshodos(blockIdx.x, detid, nhits_h3x2);
#ifdef DEBUG
	if(blockIdx.x==debug::EvRef && threadIdx.x==0){printf("YZ: nhits h3x2 %d \n", nhits_h3x2);
	for(int l = 0; l<nhits_h3x2; l++)printf("YZ: det %d chan %1.0f pos %1.4f \n", detid, hits_h3x2.chan(l), hits_h3x2.pos(l));
	}
#endif

#ifdef HODO_Y_MATCH
	detid = globalconsts::hodoplanesy[stid][0];
	int nhits_h3y1;
	const gHits hits_h3y1 = hitcolls->hitshodos(blockIdx.x, detid, nhits_h3y1);
#ifdef DEBUG
	if(blockIdx.x==debug::EvRef && threadIdx.x==0){printf("YZ: nhits h3y1 %d \n", nhits_h3y1);
	for(int l = 0; l<nhits_h3y1; l++)printf("YZ: det %d chan %1.0f pos %1.4f \n", detid, hits_h3y1.chan(l), hits_h3y1.pos(l));
	}
#endif

	detid = globalconsts::hodoplanesy[stid][1];
	int nhits_h3y2;
	const gHits hits_h3y2 = hitcolls->hitshodos(blockIdx.x, detid, nhits_h3y2);
#ifdef DEBUG
	if(blockIdx.x==debug::EvRef && threadIdx.x==0){printf("YZ: nhits h3y2 %d \n", nhits_h3y2);
	for(int l = 0; l<nhits_h3y2; l++)printf("YZ: det %d chan %1.0f pos %1.4f \n", detid, hits_h3y2.chan(l), hits_h3y2.pos(l));
	}
#endif
#endif
	
	stid = 3;//4-1
	detid = globalconsts::hodoplanesx[stid][0];
	int nhits_h4x1;
	const gHits hits_h4x1 = hitcolls->hitshodos(blockIdx.x, detid, nhits_h4x1);
#ifdef DEBUG
	if(blockIdx.x==debug::EvRef && threadIdx.x==0){printf("YZ: nhits h4x1 %d \n", nhits_h4x1);
	for(int l = 0; l<nhits_h4x1; l++)printf("YZ: det %d chan %1.0f pos %1.4f \n", detid, hits_h4x1.chan(l), hits_h4x1.pos(l));
	}
#endif

	detid = globalconsts::hodoplanesx[stid][1];
	int nhits_h4x2;
	const gHits hits_h4x2 = hitcolls->hitshodos(blockIdx.x, detid, nhits_h4x2);
#ifdef DEBUG
	if(blockIdx.x==debug::EvRef && threadIdx.x==0){printf("YZ: nhits h4x2 %d \n", nhits_h4x2);
	for(int l = 0; l<nhits_h4x2; l++)printf("YZ: det %d chan %1.0f pos %1.4f \n", detid, hits_h4x2.chan(l), hits_h4x2.pos(l));
	}
#endif
	
#ifdef HODO_Y_MATCH
	detid = globalconsts::hodoplanesy[stid][0];
	int nhits_h4y1;
	const gHits hits_h4y1 = hitcolls->hitshodos(blockIdx.x, detid, nhits_h4y1);
#ifdef DEBUG
	if(blockIdx.x==debug::EvRef && threadIdx.x==0){printf("YZ: nhits h4y1 %d \n", nhits_h4y1);
	for(int l = 0; l<nhits_h4y1; l++)printf("YZ: det %d chan %1.0f pos %1.4f \n", detid, hits_h4y1.chan(l), hits_h4y1.pos(l));
	}
#endif

	detid = globalconsts::hodoplanesy[stid][1];
	int nhits_h4y2;
	const gHits hits_h4y2 = hitcolls->hitshodos(blockIdx.x, detid, nhits_h4y2);
#ifdef DEBUG
	if(blockIdx.x==debug::EvRef && threadIdx.x==0){printf("YZ: nhits h4y2 %d \n", nhits_h4y2);
	for(int l = 0; l<nhits_h4y2; l++)printf("YZ: det %d chan %1.0f pos %1.4f \n", detid, hits_h4y2.chan(l), hits_h4y2.pos(l));
	}
#endif
#endif

#ifdef DEBUG
	if(debug::EvRef==blockIdx.x)printf("YZ: thread %d dets %d %d %d %d %d %d %d %d \n", threadIdx.x, detid_list[0], detid_list[1], detid_list[2], detid_list[3], detid_list[4], detid_list[5], detid_list[6], detid_list[7]);
#endif
	
	bool maskhodo[4];
	
	//variables for 2D track fit
	short detID[8];
	float Y[8];
	float errY[8];
	float Z[8];
	
	float A_[4];
	float Ainv_[4];
	float B_[2];
	float Par[2];
	float ParErr[2];
	float chi2;

	float y0, ty;
	float err_y0, err_ty;
	
	//Arrays for other basic hit info
	short elID[8];
	float pos[8];
	float drift[8];
	float tdc[8];
	short sign[8];

	short nhits_uv;
	
	short nhits_u2, nhits_u3;
	short nhits_v2, nhits_v3;
	
	const short nbins_total = nbins_st2*nbins_st3;
	short bin2, bin3;
	
	int nu2, nv2, nu3, nv3;
	
	int ncomb_uv3, ncomb_uv2;
	
	short i_u2, i_u3, i_v2, i_v3;
	
	int i_uv3, i_uv2, i_hit;

	float y, err_y;
	
	float chi2min = 10000.1f;

	int localbin;

	//arrays for chi2
	float dd[12];
	short hs[12];
	float res[12];
	float p1x[12];
	float p1y[12];
	float p1z[12];
	float dpx[12];
	float dpy[12];
	float dpz[12];
	float residuals[12];
	
	//get the tracks...
	const unsigned int tkl_coll_offset = blockIdx.x*datasizes::TrackSizeMax*datasizes::NTracksParam;
	const unsigned int array_thread_offset = threadIdx.x*datasizes::TrackSizeMax*datasizes::NTracksParam/THREADS_PER_BLOCK;
	
	__shared__ float besttrackYZdata[THREADS_PER_BLOCK][datasizes::NTracksParam];
	
	//gTracklet tkl;
	unsigned int Ntracks;
	const gTracks Tracks = tklcoll->tracks(blockIdx.x, threadIdx.x, Ntracks);

#ifdef DEBUG
	if(blockIdx.x==debug::EvRef)printf("YZ: actual thread %d, offset %d, ntracks %d\n", threadIdx.x, tkl_coll_offset+array_thread_offset, Ntracks ); 
#endif
		
	int trackthread;	
	float x0, tx;
	float err_x0, err_tx;
	float xmin, xmax;
	int nhits_x;
	bool update_track;
	//
	for(int i = 0; i<Ntracks; i++){
		trackthread = (int)Tracks.threadID(i);
#ifdef DEBUG
		if(blockIdx.x!=debug::EvRef){
			tklcoll->setStationID(tkl_coll_offset+array_thread_offset, i, 3);
			continue;
		}
		//if(blockIdx.x==debug::EvRef && Tracks.nHits(i)==3 && Tracks.hits_chan(i, 0)==76 && Tracks.hits_chan(i, 2)==105)
		if( (threadIdx.x%2==0 && (int)Tracks.threadID(i)%2==1) || (threadIdx.x%2==1 && (int)Tracks.threadID(i)%2==0) ){
			tklcoll->setStationID(tkl_coll_offset+array_thread_offset, i, 3);
			continue;
		}
		
		if(blockIdx.x==debug::EvRef)printf("YZ: thread %d tracklet %d thread %1.0f bin/stid %1.0f nhits %1.0f x0 %1.4f tx %1.4f y0 %1.4f ty %1.4f: \n", threadIdx.x, i, Tracks.threadID(i), Tracks.stationID(i), Tracks.nHits(i), Tracks.x0(i), Tracks.tx(i), Tracks.y0(i), Tracks.ty(i));
#endif
		x0 = Tracks.x0(i);
		tx = Tracks.tx(i);
		err_x0 = Tracks.err_x0(i);
		err_tx = Tracks.err_tx(i);
		nhits_x =  Tracks.nHits(i);
		update_track = false;
		chi2min = 10000.1f;
		
		//get the corresponding local bin!
		//binId = threadIdx.x+THREADS_PER_BLOCK*localbin;
		localbin = (Tracks.stationID(i)-trackthread)/THREADS_PER_BLOCK;
		
#ifdef DEBUG
		if(blockIdx.x==debug::EvRef)printf("YZ: actual thread %d x0 %1.4f tx %1.4f nhits %d track thread %d stid %1.0f local bin %d \n", threadIdx.x, x0, tx, nhits_x, trackthread, Tracks.stationID(i), localbin);
#endif		
		stid = 2;
		projid = 1;
		//nx1 = make_hitpairs_in_station(hits_st1x, nhits_st1x, hits_st1xp, nhits_st1xp, hitpairs_x1, hitidx1, hitidx2, hitflag1, hitflag2, stid, projid, planes, pos_exp[projid]-window[projid], pos_exp[projid]+window[projid]);
		xmin = min((tx-err_tx)*z_st2u, (tx-err_tx)*z_st2up)+x0-err_x0-det_spacing[0];
		xmax = max((tx+err_tx)*z_st2u, (tx+err_tx)*z_st2up)+x0+err_x0+det_spacing[0];
#ifdef DEBUG
		if(blockIdx.x==debug::EvRef)printf("YZ: x0 %1.4f tx %1.4f, xmin %1.4f xmax %1.4f z_st2u %1.4f  z_st2up %1.4f \n", x0, tx, xmin, xmax, z_st2u, z_st2up);
#endif		
		nu2 = make_hitpairs_in_station(hits_st2u, nhits_st2u, hits_st2up, nhits_st2up, hitpairs_u2, hitidx1, hitidx2, hitflag1, hitflag2, stid, projid, planes, xmin, xmax);

		projid = 2;
		xmin = min((tx-err_tx)*z_st2v, (tx-err_tx)*z_st2vp)+x0-err_x0-det_spacing[2];
		xmax = max((tx+err_tx)*z_st2v, (tx+err_tx)*z_st2vp)+x0+err_x0+det_spacing[2];
#ifdef DEBUG
		if(blockIdx.x==debug::EvRef)printf("YZ: x0 %1.4f tx %1.4f, xmin %1.4f xmax %1.4f z_st2v %1.4f  z_st2vp %1.4f \n", x0, tx, xmin, xmax, z_st2v, z_st2vp);
#endif		
		nv2 = make_hitpairs_in_station(hits_st2v, nhits_st2v, hits_st2vp, nhits_st2vp, hitpairs_v2, hitidx1, hitidx2, hitflag1, hitflag2, stid, projid, planes, xmin, xmax);

		stid = st3;
		projid = 1;
		xmin = min((tx-err_tx)*z_st3u, (tx-err_tx)*z_st3up)+x0-err_x0-det_spacing[4];
		xmax = max((tx+err_tx)*z_st3u, (tx+err_tx)*z_st3up)+x0+err_x0+det_spacing[4];
#ifdef DEBUG
		if(blockIdx.x==debug::EvRef)printf("YZ: x0 %1.4f tx %1.4f, xmin %1.4f xmax %1.4f z_st3u %1.4f  z_st3up %1.4f \n", x0, tx, xmin, xmax, z_st3u, z_st3up);
#endif		
		nu3 = make_hitpairs_in_station(hits_st3u, nhits_st3u, hits_st3up, nhits_st3up, hitpairs_u3, hitidx1, hitidx2, hitflag1, hitflag2, stid, projid, planes, xmin, xmax);

		projid = 2;
		projid = 2;
		xmin = min((tx-err_tx)*z_st3v, (tx-err_tx)*z_st3vp)+x0-err_x0-det_spacing[6];
		xmax = max((tx+err_tx)*z_st3v, (tx+err_tx)*z_st3vp)+x0+err_x0+det_spacing[6];
#ifdef DEBUG
		if(blockIdx.x==debug::EvRef)printf("YZ: x0 %1.4f tx %1.4f, xmin %1.4f xmax %1.4f z_st3v %1.4f  z_st3vp %1.4f \n", x0, tx, xmin, xmax, z_st3v, z_st3vp);
#endif		
		nv3 = make_hitpairs_in_station(hits_st3v, nhits_st3v, hits_st3vp, nhits_st3vp, hitpairs_v3, hitidx1, hitidx2, hitflag1, hitflag2, stid, projid, planes, xmin, xmax);
		
		tklcoll->setStationID(tkl_coll_offset+array_thread_offset, i, 3);
		
		//retrieve the bins in st2, st3
		bin2 = localbin%nbins_st2;
		bin3 = (localbin-bin2)/nbins_st2;
		
#ifdef DEBUG
		if(blockIdx.x==debug::EvRef)printf("YZ: evt %d thread %d x0 %1.4f +- %1.4f tx %1.4f +- %1.4f: nu2 %d nu3 %d nv2 %d nv3 %d \n", blockIdx.x, threadIdx.x, x0, err_x0, tx, err_tx, nu2, nu3, nv2, nv3);
#endif		
		if(nu2 == 0 || nu3==0) continue;
		if(nv2 == 0 || nv3==0) continue;
		
		ncomb_uv3 = nu3*nv3;
		ncomb_uv2 = nu2*nv2;
		
		for(int m = 0; m<nhits_x; m++){
			detid = (Tracks.hits_detid(i, m));
			chan = (Tracks.hits_chan(i, m));
			dd[m] = (Tracks.hits_drift(i, m));
			hs[m] = (Tracks.hits_sign(i, m));
			res[m] = planes->resolution[detid];
			p1x[m] = x_bep(detid, chan, planes);
			p1y[m] = y_bep(detid, chan, planes);
			p1z[m] = z_bep(detid, chan, planes);
			dpx[m] = planes->deltapx[detid];
			dpy[m] = planes->deltapy[detid];
			dpz[m] = planes->deltapz[detid];

#ifdef DEBUG			
			if(blockIdx.x==debug::EvRef)printf("YZ: evt %d thread %d hit %d sign %d drift %1.4f p1x %1.4f p1y %1.4f p1z %1.4f dpx %1.4f dpy %1.4f dpz %1.4f  \n", blockIdx.x, threadIdx.x, m, hs[m], dd[m], p1x[m], p1y[m], p1z[m], dpx[m], dpy[m], dpz[m]);
#endif
		}
				
		//ty = 0;
		
		for(i_uv3 = 0; i_uv3<ncomb_uv3; i_uv3++){
			i_u3 = i_uv3%nu3;
			i_v3 = (i_uv3-i_u3)/nu3;
			
			nhits_uv = 0;
			//bin3+nbins_st3*i_u3
			if(hitpairs_u3[i_u3].first>=0){
				detID[nhits_uv] = detid_list[4];
				i_hit = hitpairs_u3[i_u3].first;
				Z[nhits_uv] = z_st3u;
				elID[nhits_uv] = (short)hits_st3u.chan(i_hit);
				tdc[nhits_uv] = hits_st3u.tdc(i_hit);
				sign[nhits_uv] = 0;
				drift[nhits_uv] = hits_st3u.drift(i_hit);
				pos[nhits_uv] = hits_st3u.pos(i_hit);
				if(calculate_y_uvhit(detID[nhits_uv], elID[nhits_uv], drift[nhits_uv], 0, x0, tx, planes, y, err_y)){
					res[nhits_x+nhits_uv] = planes->resolution[detID[nhits_uv]];
					dd[nhits_x+nhits_uv] = drift[nhits_uv];
					hs[nhits_x+nhits_uv] = sign[nhits_uv];
					p1x[nhits_x+nhits_uv] = x_bep(detID[nhits_uv], elID[nhits_uv], planes);
					p1y[nhits_x+nhits_uv] = y_bep(detID[nhits_uv], elID[nhits_uv], planes);
					p1z[nhits_x+nhits_uv] = z_bep(detID[nhits_uv], elID[nhits_uv], planes);
					dpx[nhits_x+nhits_uv] = planes->deltapx[detID[nhits_uv]];
					dpy[nhits_x+nhits_uv] = planes->deltapy[detID[nhits_uv]];
					dpz[nhits_x+nhits_uv] = planes->deltapz[detID[nhits_uv]];
					
#ifdef DEBUG
					if(blockIdx.x==debug::EvRef)printf("YZ: det %d chan %1.0f pos %1.4f drift %1.4f\n", detID[nhits_uv], elID[nhits_uv], pos[nhits_uv], drift[nhits_uv]);
					if(blockIdx.x==debug::EvRef)printf("YZ: evt %d thread %d hit %d sign %d drift %1.4f p1x %1.4f p1y %1.4f p1z %1.4f dpx %1.4f dpy %1.4f dpz %1.4f  \n", blockIdx.x, threadIdx.x, nhits_x+nhits_uv, hs[nhits_x+nhits_uv], dd[nhits_x+nhits_uv], p1x[nhits_x+nhits_uv], p1y[nhits_x+nhits_uv], p1z[nhits_x+nhits_uv], dpx[nhits_x+nhits_uv], dpy[nhits_x+nhits_uv], dpz[nhits_x+nhits_uv]);
#endif
					
					Y[nhits_uv] = y;
					errY[nhits_uv] = err_y;
					nhits_uv++;
					//ty+= y/z_st3u;
				}
			}
			if(hitpairs_u3[i_u3].second>=0){
				detID[nhits_uv] = detid_list[5];
				i_hit = hitpairs_u3[i_u3].second;
				Z[nhits_uv] = z_st3up;
				elID[nhits_uv] = (short)hits_st3up.chan(i_hit);
				tdc[nhits_uv] = hits_st3up.tdc(i_hit);
				sign[nhits_uv] = 0;
				drift[nhits_uv] = hits_st3up.drift(i_hit);
				pos[nhits_uv] = hits_st3up.pos(i_hit);
				if(calculate_y_uvhit(detID[nhits_uv], elID[nhits_uv], drift[nhits_uv], 0, x0, tx, planes, y, err_y)){
					res[nhits_x+nhits_uv] = planes->resolution[detID[nhits_uv]];
					dd[nhits_x+nhits_uv] = drift[nhits_uv];
					hs[nhits_x+nhits_uv] = sign[nhits_uv];
					p1x[nhits_x+nhits_uv] = x_bep(detID[nhits_uv], elID[nhits_uv], planes);
					p1y[nhits_x+nhits_uv] = y_bep(detID[nhits_uv], elID[nhits_uv], planes);
					p1z[nhits_x+nhits_uv] = z_bep(detID[nhits_uv], elID[nhits_uv], planes);
					dpx[nhits_x+nhits_uv] = planes->deltapx[detID[nhits_uv]];
					dpy[nhits_x+nhits_uv] = planes->deltapy[detID[nhits_uv]];
					dpz[nhits_x+nhits_uv] = planes->deltapz[detID[nhits_uv]];

#ifdef DEBUG
					if(blockIdx.x==debug::EvRef)printf("YZ: evt %d thread %d hit %d sign %d drift %1.4f p1x %1.4f p1y %1.4f p1z %1.4f dpx %1.4f dpy %1.4f dpz %1.4f  \n", 						if(blockIdx.x==debug::EvRef)printf("YZ: det %d chan %1.0f pos %1.4f drift %1.4f\n", detID[nhits_uv], elID[nhits_uv], pos[nhits_uv], drift[nhits_uv]);
blockIdx.x, threadIdx.x, nhits_x+nhits_uv, hs[nhits_x+nhits_uv], dd[nhits_x+nhits_uv], p1x[nhits_x+nhits_uv], p1y[nhits_x+nhits_uv], p1z[nhits_x+nhits_uv], dpx[nhits_x+nhits_uv], dpy[nhits_x+nhits_uv], dpz[nhits_x+nhits_uv]);
#endif

					Y[nhits_uv] = y;
					errY[nhits_uv] = err_y;
					nhits_uv++;
					//ty+= y/z_st3up;
				}
			}
			
			nhits_u3 = nhits_uv;
			if(nhits_u3==0) continue;
			
			if(hitpairs_v3[i_v3].first>=0){
				detID[nhits_uv] = detid_list[6];
				i_hit = hitpairs_v3[i_v3].first;
				Z[nhits_uv] = z_st3v;
				elID[nhits_uv] = (short)hits_st3v.chan(i_hit);
				tdc[nhits_uv] = hits_st3v.tdc(i_hit);
				sign[nhits_uv] = 0;
				drift[nhits_uv] = hits_st3v.drift(i_hit);
				pos[nhits_uv] = hits_st3v.pos(i_hit);
				if(calculate_y_uvhit(detID[nhits_uv], elID[nhits_uv], drift[nhits_uv], 0, x0, tx, planes, y, err_y)){
					res[nhits_x+nhits_uv] = planes->resolution[detID[nhits_uv]];
					dd[nhits_x+nhits_uv] = drift[nhits_uv];
					hs[nhits_x+nhits_uv] = sign[nhits_uv];
					p1x[nhits_x+nhits_uv] = x_bep(detID[nhits_uv], elID[nhits_uv], planes);
					p1y[nhits_x+nhits_uv] = y_bep(detID[nhits_uv], elID[nhits_uv], planes);
					p1z[nhits_x+nhits_uv] = z_bep(detID[nhits_uv], elID[nhits_uv], planes);
					dpx[nhits_x+nhits_uv] = planes->deltapx[detID[nhits_uv]];
					dpy[nhits_x+nhits_uv] = planes->deltapy[detID[nhits_uv]];
					dpz[nhits_x+nhits_uv] = planes->deltapz[detID[nhits_uv]];

#ifdef DEBUG
					if(blockIdx.x==debug::EvRef)printf("YZ: det %d chan %1.0f pos %1.4f drift %1.4f\n", detID[nhits_uv], elID[nhits_uv], pos[nhits_uv], drift[nhits_uv]);
					if(blockIdx.x==debug::EvRef)printf("YZ: evt %d thread %d hit %d sign %d drift %1.4f p1x %1.4f p1y %1.4f p1z %1.4f dpx %1.4f dpy %1.4f dpz %1.4f  \n", blockIdx.x, threadIdx.x, nhits_x+nhits_uv, hs[nhits_x+nhits_uv], dd[nhits_x+nhits_uv], p1x[nhits_x+nhits_uv], p1y[nhits_x+nhits_uv], p1z[nhits_x+nhits_uv], dpx[nhits_x+nhits_uv], dpy[nhits_x+nhits_uv], dpz[nhits_x+nhits_uv]);
#endif


					Y[nhits_uv] = y;
					errY[nhits_uv] = err_y;
					nhits_uv++;
					//ty+= y/z_st3v;
				}
			}
			if(hitpairs_v3[i_v3].second>=0){
				detID[nhits_uv] = detid_list[7];
				i_hit = hitpairs_v3[i_v3].second;
				Z[nhits_uv] = z_st3vp;
				elID[nhits_uv] = (short)hits_st3vp.chan(i_hit);
				tdc[nhits_uv] = hits_st3vp.tdc(i_hit);
				sign[nhits_uv] = 0;
				drift[nhits_uv] = hits_st3vp.drift(i_hit);
				pos[nhits_uv] = hits_st3vp.pos(i_hit);
				if(calculate_y_uvhit(detID[nhits_uv], elID[nhits_uv], drift[nhits_uv], 0, x0, tx, planes, y, err_y)){
					res[nhits_x+nhits_uv] = planes->resolution[detID[nhits_uv]];
					dd[nhits_x+nhits_uv] = drift[nhits_uv];
					hs[nhits_x+nhits_uv] = sign[nhits_uv];
					p1x[nhits_x+nhits_uv] = x_bep(detID[nhits_uv], elID[nhits_uv], planes);
					p1y[nhits_x+nhits_uv] = y_bep(detID[nhits_uv], elID[nhits_uv], planes);
					p1z[nhits_x+nhits_uv] = z_bep(detID[nhits_uv], elID[nhits_uv], planes);
					dpx[nhits_x+nhits_uv] = planes->deltapx[detID[nhits_uv]];
					dpy[nhits_x+nhits_uv] = planes->deltapy[detID[nhits_uv]];
					dpz[nhits_x+nhits_uv] = planes->deltapz[detID[nhits_uv]];
					
#ifdef DEBUG
					if(blockIdx.x==debug::EvRef)printf("YZ: det %d chan %1.0f pos %1.4f drift %1.4f\n", detID[nhits_uv], elID[nhits_uv], pos[nhits_uv], drift[nhits_uv]);
					if(blockIdx.x==debug::EvRef)printf("YZ: evt %d thread %d hit %d sign %d drift %1.4f p1x %1.4f p1y %1.4f p1z %1.4f dpx %1.4f dpy %1.4f dpz %1.4f  \n", blockIdx.x, threadIdx.x, nhits_x+nhits_uv, hs[nhits_x+nhits_uv], dd[nhits_x+nhits_uv], p1x[nhits_x+nhits_uv], p1y[nhits_x+nhits_uv], p1z[nhits_x+nhits_uv], dpx[nhits_x+nhits_uv], dpy[nhits_x+nhits_uv], dpz[nhits_x+nhits_uv]);
#endif

					Y[nhits_uv] = y;
					errY[nhits_uv] = err_y;
					nhits_uv++;
					//ty+= y/z_st3vp;
				}
			}
			
			nhits_v3 = nhits_uv-nhits_u3;
			if(nhits_v3==0) continue;

			//ty = ty/nhits_uv;
			
			for(i_uv2 = 0; i_uv2<ncomb_uv2; i_uv2++){
				i_u2 = i_uv2%nu2;
				i_v2 = (i_uv2-i_u2)/nu2;

				nhits_uv = nhits_u3+nhits_v3;
				
				if(hitpairs_u2[i_u2].first>=0){
					detID[nhits_uv] = detid_list[0];
					i_hit = hitpairs_u2[i_u2].first;
					Z[nhits_uv] = z_st2u;
					elID[nhits_uv] = (short)hits_st2u.chan(i_hit);
					tdc[nhits_uv] = hits_st2u.tdc(i_hit);
					sign[nhits_uv] = 0;
					drift[nhits_uv] = hits_st2u.drift(i_hit);
					pos[nhits_uv] = hits_st2u.pos(i_hit);
					if(calculate_y_uvhit(detID[nhits_uv], elID[nhits_uv], drift[nhits_uv], 0, x0, tx, planes, y, err_y)){
						//if( fabs(y-ty*z_st2u)/err_y<=20.0f ){//since ty is *very* rough let's be generous...				
							res[nhits_x+nhits_uv] = planes->resolution[detID[nhits_uv]];
							dd[nhits_x+nhits_uv] = drift[nhits_uv];
							hs[nhits_x+nhits_uv] = sign[nhits_uv];
							p1x[nhits_x+nhits_uv] = x_bep(detID[nhits_uv], elID[nhits_uv], planes);
							p1y[nhits_x+nhits_uv] = y_bep(detID[nhits_uv], elID[nhits_uv], planes);
							p1z[nhits_x+nhits_uv] = z_bep(detID[nhits_uv], elID[nhits_uv], planes);
							dpx[nhits_x+nhits_uv] = planes->deltapx[detID[nhits_uv]];
							dpy[nhits_x+nhits_uv] = planes->deltapy[detID[nhits_uv]];
							dpz[nhits_x+nhits_uv] = planes->deltapz[detID[nhits_uv]];

#ifdef DEBUG
							if(blockIdx.x==debug::EvRef)printf("YZ: det %d chan %1.0f pos %1.4f drift %1.4f\n", detID[nhits_uv], elID[nhits_uv], pos[nhits_uv], drift[nhits_uv]);
							if(blockIdx.x==debug::EvRef)printf("YZ: evt %d thread %d hit %d sign %d drift %1.4f p1x %1.4f p1y %1.4f p1z %1.4f dpx %1.4f dpy %1.4f dpz %1.4f  \n", blockIdx.x, threadIdx.x, nhits_x+nhits_uv, hs[nhits_x+nhits_uv], dd[nhits_x+nhits_uv], p1x[nhits_x+nhits_uv], p1y[nhits_x+nhits_uv], p1z[nhits_x+nhits_uv], dpx[nhits_x+nhits_uv], dpy[nhits_x+nhits_uv], dpz[nhits_x+nhits_uv]);
#endif
							
							Y[nhits_uv] = y;
							errY[nhits_uv] = err_y;
							nhits_uv++;
						//}
					}
				}
				if(hitpairs_u2[i_u2].second>=0){
					detID[nhits_uv] = detid_list[1];
					i_hit = hitpairs_u2[i_u2].second;
					Z[nhits_uv] = z_st2up;
					elID[nhits_uv] = (short)hits_st2up.chan(i_hit);
					tdc[nhits_uv] = hits_st2up.tdc(i_hit);
					sign[nhits_uv] = 0;
					drift[nhits_uv] = hits_st2up.drift(i_hit);
					pos[nhits_uv] = hits_st2up.pos(i_hit);
					if(calculate_y_uvhit(detID[nhits_uv], elID[nhits_uv], drift[nhits_uv], 0, x0, tx, planes, y, err_y)){
						//if( fabs(y-ty*z_st2up)/err_y<=20.0f ){//since ty is *very* rough let's be generous...				
							res[nhits_x+nhits_uv] = planes->resolution[detID[nhits_uv]];
							dd[nhits_x+nhits_uv] = drift[nhits_uv];
							hs[nhits_x+nhits_uv] = sign[nhits_uv];
							p1x[nhits_x+nhits_uv] = x_bep(detID[nhits_uv], elID[nhits_uv], planes);
							p1y[nhits_x+nhits_uv] = y_bep(detID[nhits_uv], elID[nhits_uv], planes);
							p1z[nhits_x+nhits_uv] = z_bep(detID[nhits_uv], elID[nhits_uv], planes);
							dpx[nhits_x+nhits_uv] = planes->deltapx[detID[nhits_uv]];
							dpy[nhits_x+nhits_uv] = planes->deltapy[detID[nhits_uv]];
							dpz[nhits_x+nhits_uv] = planes->deltapz[detID[nhits_uv]];

#ifdef DEBUG
							if(blockIdx.x==debug::EvRef)printf("YZ: det %d chan %1.0f pos %1.4f drift %1.4f\n", detID[nhits_uv], elID[nhits_uv], pos[nhits_uv], drift[nhits_uv]);
							if(blockIdx.x==debug::EvRef)printf("YZ: evt %d thread %d hit %d sign %d drift %1.4f p1x %1.4f p1y %1.4f p1z %1.4f dpx %1.4f dpy %1.4f dpz %1.4f  \n", blockIdx.x, threadIdx.x, nhits_x+nhits_uv, hs[nhits_x+nhits_uv], dd[nhits_x+nhits_uv], p1x[nhits_x+nhits_uv], p1y[nhits_x+nhits_uv], p1z[nhits_x+nhits_uv], dpx[nhits_x+nhits_uv], dpy[nhits_x+nhits_uv], dpz[nhits_x+nhits_uv]);
#endif

							Y[nhits_uv] = y;
							errY[nhits_uv] = err_y;
							nhits_uv++;
						//}
					}
				}
				
				nhits_u2 = nhits_uv-nhits_u3-nhits_v3;
				if(nhits_u2==0) continue;
				
				if(hitpairs_v2[i_v2].first>=0){
					detID[nhits_uv] = detid_list[2];
					i_hit = hitpairs_v2[i_v2].first;
					Z[nhits_uv] = z_st2v;
					elID[nhits_uv] = (short)hits_st2v.chan(i_hit);
					tdc[nhits_uv] = hits_st2v.tdc(i_hit);
					sign[nhits_uv] = 0;
					drift[nhits_uv] = hits_st2v.drift(i_hit);
					pos[nhits_uv] = hits_st2v.pos(i_hit);
					if(calculate_y_uvhit(detID[nhits_uv], elID[nhits_uv], drift[nhits_uv], 0, x0, tx, planes, y, err_y)){
						//if( fabs(y-ty*z_st2v)/err_y<=20.0f ){//since ty is *very* rough let's be generous...				
							res[nhits_x+nhits_uv] = planes->resolution[detID[nhits_uv]];
							dd[nhits_x+nhits_uv] = drift[nhits_uv];
							hs[nhits_x+nhits_uv] = sign[nhits_uv];
							p1x[nhits_x+nhits_uv] = x_bep(detID[nhits_uv], elID[nhits_uv], planes);
							p1y[nhits_x+nhits_uv] = y_bep(detID[nhits_uv], elID[nhits_uv], planes);
							p1z[nhits_x+nhits_uv] = z_bep(detID[nhits_uv], elID[nhits_uv], planes);
							dpx[nhits_x+nhits_uv] = planes->deltapx[detID[nhits_uv]];
							dpy[nhits_x+nhits_uv] = planes->deltapy[detID[nhits_uv]];
							dpz[nhits_x+nhits_uv] = planes->deltapz[detID[nhits_uv]];

#ifdef DEBUG
							if(blockIdx.x==debug::EvRef)printf("YZ: det %d chan %1.0f pos %1.4f drift %1.4f\n", detID[nhits_uv], elID[nhits_uv], pos[nhits_uv], drift[nhits_uv]);
							if(blockIdx.x==debug::EvRef)printf("YZ: evt %d thread %d hit %d sign %d drift %1.4f p1x %1.4f p1y %1.4f p1z %1.4f dpx %1.4f dpy %1.4f dpz %1.4f  \n", blockIdx.x, threadIdx.x, nhits_x+nhits_uv, hs[nhits_x+nhits_uv], dd[nhits_x+nhits_uv], p1x[nhits_x+nhits_uv], p1y[nhits_x+nhits_uv], p1z[nhits_x+nhits_uv], dpx[nhits_x+nhits_uv], dpy[nhits_x+nhits_uv], dpz[nhits_x+nhits_uv]);
#endif
							
							Y[nhits_uv] = y;
							errY[nhits_uv] = err_y;
							nhits_uv++;
						//}
					}
				}
				if(hitpairs_v2[i_v2].second>=0){
					detID[nhits_uv] = detid_list[3];
					i_hit = hitpairs_v2[i_v2].second;
					Z[nhits_uv] = z_st2vp;
					elID[nhits_uv] = (short)hits_st2vp.chan(i_hit);
					tdc[nhits_uv] = hits_st2vp.tdc(i_hit);
					sign[nhits_uv] = 0;
					drift[nhits_uv] = hits_st2vp.drift(i_hit);
					pos[nhits_uv] = hits_st2vp.pos(i_hit);
					if(calculate_y_uvhit(detID[nhits_uv], elID[nhits_uv], drift[nhits_uv], 0, x0, tx, planes, y, err_y)){
						//if( fabs(y-ty*z_st2vp)/err_y<=20.0f ){//since ty is *very* rough let's be generous...				
							res[nhits_x+nhits_uv] = planes->resolution[detID[nhits_uv]];
							dd[nhits_x+nhits_uv] = drift[nhits_uv];
							hs[nhits_x+nhits_uv] = sign[nhits_uv];
							p1x[nhits_x+nhits_uv] = x_bep(detID[nhits_uv], elID[nhits_uv], planes);
							p1y[nhits_x+nhits_uv] = y_bep(detID[nhits_uv], elID[nhits_uv], planes);
							p1z[nhits_x+nhits_uv] = z_bep(detID[nhits_uv], elID[nhits_uv], planes);
							dpx[nhits_x+nhits_uv] = planes->deltapx[detID[nhits_uv]];
							dpy[nhits_x+nhits_uv] = planes->deltapy[detID[nhits_uv]];
							dpz[nhits_x+nhits_uv] = planes->deltapz[detID[nhits_uv]];
							
#ifdef DEBUG
							if(blockIdx.x==debug::EvRef)printf("YZ: det %d chan %1.0f pos %1.4f drift %1.4f\n", detID[nhits_uv], elID[nhits_uv], pos[nhits_uv], drift[nhits_uv]);
							if(blockIdx.x==debug::EvRef)printf("YZ: evt %d thread %d hit %d sign %d drift %1.4f p1x %1.4f p1y %1.4f p1z %1.4f dpx %1.4f dpy %1.4f dpz %1.4f  \n", blockIdx.x, threadIdx.x, nhits_x+nhits_uv, hs[nhits_x+nhits_uv], dd[nhits_x+nhits_uv], p1x[nhits_x+nhits_uv], p1y[nhits_x+nhits_uv], p1z[nhits_x+nhits_uv], dpx[nhits_x+nhits_uv], dpy[nhits_x+nhits_uv], dpz[nhits_x+nhits_uv]);
#endif
							Y[nhits_uv] = y;
							errY[nhits_uv] = err_y;
							nhits_uv++;
						//}
					}
				}
				
				nhits_v2 = nhits_uv-nhits_u3-nhits_v3-nhits_u2;
				if(nhits_v2==0) continue;
				
				fit_2D_track(nhits_uv, Y, Z, errY, A_, Ainv_, B_, Par, ParErr, chi2);
				
				y0 = Par[0];
				ty = Par[1];

				err_y0 = ParErr[0];
				err_ty = ParErr[1];

								
				if(fabs(y0)>Y0_MAX+2*err_y0 || fabs(ty)>TY_MAX+2*err_ty)continue;
				//if(fabs(y0+ty*globalconsts::Z_KMAG_BEND)>globalconsts::Y_KMAG_BEND)continue;

				//LR ambiguity resolution
				resolve_leftright_newhits(x0, tx, y0, ty, err_x0, err_tx, err_y0, err_ty, nhits_uv, detID, pos, drift, sign, planes, 150.);
				resolve_single_leftright_newhits(x0, tx, y0, ty, nhits_uv, detID, pos, sign, planes);
				
#ifdef DEBUG
				if(blockIdx.x==debug::EvRef)printf("YZ: thread %d combi %d-%d-%d-%d \n", threadIdx.x, i_u3, i_v3, i_u2, i_v2);				
#endif
				for(int ll = 0; ll<nhits_uv; ll++){
					hs[nhits_x+ll] = sign[ll];
#ifdef DEBUG
					if(blockIdx.x==debug::EvRef)printf(" thread %d  hit %d det %d chan %d Z %1.4f Y %1.4f ;\n", threadIdx.x, ll, detID[ll], elID[ll], Z[ll], Y[ll]);
#endif
					//Y[ll]+= sign[ll]*drift[ll]*planes->sintheta[detID[ll]];
				}
				fit_2D_track(nhits_uv, Y, Z, errY, A_, Ainv_, B_, Par, ParErr, chi2);
#ifdef DEBUG
				if(blockIdx.x==debug::EvRef)printf("thread %d YZ: y0 %1.4f ty %1.4f \n", threadIdx.x, Par[0], Par[1]);				
#endif
				y0 = Par[0];
				ty = Par[1];

				err_y0 = ParErr[0];
				err_ty = ParErr[1];
				
				if(fabs(y0)>Y0_MAX || fabs(ty)>TY_MAX)continue;
								
#ifdef PROP_Y_MATCH
				//prop matching
				nprop = 0;
				checknext = true;
				
				for(int n = 0; n<nhits_p1y1; n++){
					ipos = hits_p1y1.pos(n);
					yExp = ty*z_p1y1+y0;
#ifdef DEBUG
					if(blockIdx.x==debug::EvRef)printf("evt %d p1y1, ipos = %1.4f, yExp = %1.4f, diff = %1.4f \n", blockIdx.x, ipos, yExp, ipos-yExp);
#endif
					if(fabs(ipos-yExp)<5.08f){
						nprop++;
						checknext = false;
						break;
					}
				}
				if(checknext){
					for(int n = 0; n<nhits_p1y2; n++){
						ipos = hits_p1y2.pos(n);
						yExp = ty*z_p1y2+y0;
#ifdef DEBUG
						if(blockIdx.x<=debug::EvRef)printf("evt %d p1x2, ipos = %1.4f, yExp = %1.4f, diff = %1.4f \n", blockIdx.x, ipos, yExp, ipos-yExp);
#endif
						if(fabs(ipos-yExp)<5.08f){
							nprop++;
//							checknext = false;
							break;
						}
					}
				}
				checknext = true;
				
//				if(checknext){
				for(int n = 0; n<nhits_p2y1; n++){
					ipos = hits_p2y1.pos(n);
					yExp = ty*z_p2y1+y0;
#ifdef DEBUG
					if(blockIdx.x<=debug::EvRef)printf("evt %d p2x1, ipos = %1.4f, yExp = %1.4f, diff = %1.4f \n", blockIdx.x, ipos, yExp, ipos-yExp);
#endif
					if(fabs(ipos-yExp)<10.16f){
						nprop++;
						checknext = false;
						break;
					}
				}
//				}
				if(checknext){
					for(int n = 0; n<nhits_p2y2; n++){
						ipos = hits_p2y2.pos(n);
						yExp = ty*z_p2y2+y0;
#ifdef DEBUG
						if(blockIdx.x<=debug::EvRef)printf("evt %d p2y2, ipos = %1.4f, yExp = %1.4f, diff = %1.4f \n", blockIdx.x, ipos, yExp, ipos-yExp);
#endif
						if(fabs(ipos-yExp)<10.16f){
							nprop++;
//							checknext = false;
							break;
						}
					}
				}
				if(nprop<selection::NpropXYhitsMin)continue;
#endif	

#ifdef DEBUG
				if(blockIdx.x==debug::EvRef)printf(" evt %d x0 %1.4f +- %1.4f tx %1.4f +- %1.4f y0 %1.4f +- %1.4f ty %1.4f +- %1.4f \n", blockIdx.x, x0, err_x0, tx, err_tx, y0, err_y0, ty, err_tx);
#endif
				//hodoscope matching
				stid = 1;//2-1

				maskhodo[stid] = 0;
				detid = globalconsts::hodoplanesx[stid][0];
				maskhodo[stid] = match_tracklet_to_hodo(stid, detid, nhits_h2x1, hits_h2x1, x0, y0, tx, ty, err_x0, err_y0, err_tx, err_ty, planes);
				if(!maskhodo[stid]){
					detid = globalconsts::hodoplanesx[stid][1];
					maskhodo[stid] = maskhodo[stid] || match_tracklet_to_hodo(stid, detid, nhits_h2x2, hits_h2x2, x0, y0, tx, ty, err_x0, err_y0, err_tx, err_ty, planes);
#ifdef HODO_Y_MATCH
					if(!maskhodo[stid]){
						detid = globalconsts::hodoplanesy[stid][0];
						maskhodo[stid] = maskhodo[stid] || match_tracklet_to_hodo(stid, detid, nhits_h2y1, hits_h2y1, x0, y0, tx, ty, err_x0, err_y0, err_tx, err_ty, planes);
						if(!maskhodo[stid]){
							detid = globalconsts::hodoplanesy[stid][1];
							maskhodo[stid] = maskhodo[stid] || match_tracklet_to_hodo(stid, detid, nhits_h2y2, hits_h2y2, x0, y0, tx, ty, err_x0, err_y0, err_tx, err_ty, planes);
						}
					}
#endif
				}

				if(!maskhodo[stid])continue;
				
				stid = 2;//3-1
				maskhodo[stid] = 0;
				detid = globalconsts::hodoplanesx[stid][0];
				maskhodo[stid] = match_tracklet_to_hodo(stid, detid, nhits_h3x1, hits_h3x1, x0, y0, tx, ty, err_x0, err_y0, err_tx, err_ty, planes);
				if(!maskhodo[stid]){
					detid = globalconsts::hodoplanesx[stid][1];
					maskhodo[stid] = maskhodo[stid] || match_tracklet_to_hodo(stid, detid, nhits_h3x2, hits_h3x2, x0, y0, tx, ty, err_x0, err_y0, err_tx, err_ty, planes);
#ifdef HODO_Y_MATCH
					if(!maskhodo[stid]){
						detid = globalconsts::hodoplanesy[stid][0];
						maskhodo[stid] = maskhodo[stid] || match_tracklet_to_hodo(stid, detid, nhits_h3y1, hits_h3y1, x0, y0, tx, ty, err_x0, err_y0, err_tx, err_ty, planes);
						if(!maskhodo[stid]){
							detid = globalconsts::hodoplanesy[stid][1];
							maskhodo[stid] = maskhodo[stid] || match_tracklet_to_hodo(stid, detid, nhits_h3y2, hits_h3y2, x0, y0, tx, ty, err_x0, err_y0, err_tx, err_ty, planes);
						}
					}
#endif
				}

				if(!maskhodo[stid])continue;
				
				stid = 3;//4-1
				maskhodo[stid] = 0;
				detid = globalconsts::hodoplanesx[stid][0];
				maskhodo[stid] = match_tracklet_to_hodo(stid, detid, nhits_h4x1, hits_h4x1, x0, y0, tx, ty, err_x0, err_y0, err_tx, err_ty, planes);
				if(!maskhodo[stid]){
					detid = globalconsts::hodoplanesx[stid][1];
					maskhodo[stid] = maskhodo[stid] || match_tracklet_to_hodo(stid, detid, nhits_h4x2, hits_h4x2, x0, y0, tx, ty, err_x0, err_y0, err_tx, err_ty, planes);
#ifdef HODO_Y_MATCH
					if(!maskhodo[stid]){
						detid = globalconsts::hodoplanesy[stid][0];
						maskhodo[stid] = maskhodo[stid] || match_tracklet_to_hodo(stid, detid, nhits_h4y1, hits_h4y1, x0, y0, tx, ty, err_x0, err_y0, err_tx, err_ty, planes);
						if(!maskhodo[stid]){
							detid = globalconsts::hodoplanesy[stid][1];
							maskhodo[stid] = maskhodo[stid] || match_tracklet_to_hodo(stid, detid, nhits_h4y2, hits_h4y2, x0, y0, tx, ty, err_x0, err_y0, err_tx, err_ty, planes);
						}
					}
#endif
				}
				if(!maskhodo[stid])continue;
				
				
				//chi2 evaluation of track candidate
				chi2 = chi2_track(nhits_x+nhits_uv, residuals, dd, hs, res, p1x, p1y, p1z, dpx, dpy, dpz, x0, y0, tx, ty);
#ifdef DEBUG	
				if(blockIdx.x==debug::EvRef)printf("thread %d YZ: combi %d-%d-%d-%d, chi2 %1.4f \n", threadIdx.x, i_u3, i_v3, i_u2, i_v2, chi2);				
#endif
				//if(chi2>1000000)continue;
				if(chi2<chi2min){
					chi2min = chi2;
					update_track = true;
					besttrackYZdata[threadIdx.x][2] = nhits_uv;
					besttrackYZdata[threadIdx.x][3] = chi2;
					besttrackYZdata[threadIdx.x][6] = ty;
					besttrackYZdata[threadIdx.x][8] = y0;
					besttrackYZdata[threadIdx.x][11] = err_ty;
					besttrackYZdata[threadIdx.x][13] = err_y0;
				
					for(int n = 0; n<nhits_uv;n++){
					besttrackYZdata[threadIdx.x][16+n] = detID[n];
					besttrackYZdata[threadIdx.x][34+n] = elID[n];
					besttrackYZdata[threadIdx.x][52+n] = pos[n];
					besttrackYZdata[threadIdx.x][70+n] = drift[n];
					besttrackYZdata[threadIdx.x][88+n] = sign[n];
					besttrackYZdata[threadIdx.x][106+n] = tdc[n];
					//fill in the residuals for x hits
					if(n<nhits_x)besttrackYZdata[threadIdx.x][124+n] = residuals[n];
					besttrackYZdata[threadIdx.x][128+n] = residuals[nhits_x+n];
					}
				}
				
			}
		}
		
		if(update_track){
			tklcoll->setStationID(tkl_coll_offset+array_thread_offset, i, 5);
			nhits_x = Tracks.nHits(i);
			nhits_uv = besttrackYZdata[threadIdx.x][2];
			tklcoll->setnHits(tkl_coll_offset+array_thread_offset, i, nhits_x+besttrackYZdata[threadIdx.x][2]);
			tklcoll->setChisq(tkl_coll_offset+array_thread_offset, i, besttrackYZdata[threadIdx.x][3]);
			tklcoll->setTy(tkl_coll_offset+array_thread_offset, i, besttrackYZdata[threadIdx.x][6]);
			tklcoll->setY0(tkl_coll_offset+array_thread_offset, i, besttrackYZdata[threadIdx.x][8]);
			tklcoll->setErrTy(tkl_coll_offset+array_thread_offset, i, besttrackYZdata[threadIdx.x][11]);
			tklcoll->setErrY0(tkl_coll_offset+array_thread_offset, i, besttrackYZdata[threadIdx.x][13]);
			
			for(int n = 0; n<nhits_uv; n++){
				tklcoll->setHitDetID(tkl_coll_offset+array_thread_offset, i, nhits_x+n, besttrackYZdata[threadIdx.x][16+n]);
				tklcoll->setHitChan(tkl_coll_offset+array_thread_offset, i, nhits_x+n, besttrackYZdata[threadIdx.x][34+n]);
				tklcoll->setHitPos(tkl_coll_offset+array_thread_offset, i, nhits_x+n, besttrackYZdata[threadIdx.x][52+n]);
				tklcoll->setHitDrift(tkl_coll_offset+array_thread_offset, i, nhits_x+n, besttrackYZdata[threadIdx.x][70+n]);
				tklcoll->setHitSign(tkl_coll_offset+array_thread_offset, i, nhits_x+n, besttrackYZdata[threadIdx.x][88+n]);
				tklcoll->setHitTDC(tkl_coll_offset+array_thread_offset, i, nhits_x+n, besttrackYZdata[threadIdx.x][106+n]);
				if(n<nhits_x)tklcoll->setHitResidual(tkl_coll_offset+array_thread_offset, i, n, besttrackYZdata[threadIdx.x][124+n]);
				tklcoll->setHitResidual(tkl_coll_offset+array_thread_offset, i, nhits_x+n, besttrackYZdata[threadIdx.x][128+n]);
			}
		}
		
		
	}//end loop on existing tracklets
	
	
	
}


////////////////////////////////////
//
//          GLOBAL TRACKING
//
////////////////////////////////////

__global__ void gKernel_Global_tracking(
	gEventHitCollections* hitcolls,
	gEventTrackCollection* tklcoll,
	const gPlane* planes,
#ifdef DEBUG
	int* eventID,
#endif
	bool* hastoomanyhits)
{
	if(hastoomanyhits[blockIdx.x]){
#ifdef DEBUG
		if(threadIdx.x==0)printf("Evt %d discarded, too many hits\n", eventID[blockIdx.x]);
#endif
		return;
	}
	
	short hitidx1[100];
	short hitidx2[100];
	short hitflag1[100];
	short hitflag2[100];
	
	int nx1, nu1, nv1;
	
        //pairs in station 1
        thrust::pair<int, int> hitpairs_x1[100];
        thrust::pair<int, int> hitpairs_u1[100];
        thrust::pair<int, int> hitpairs_v1[100];
	
	//get the hits
	unsigned int offset_hitcoll;
	
	short stid, projid, detid, detoff;
	
	projid = 0;
	stid = 0;
	detoff = 1;
	short detid_list[8];
	
	//Get the required hit collections here!
	projid = 0;
	detid = globalconsts::detsuperid[stid][projid]*2;
	detid_list[0] = globalconsts::eff_detid_chambers[detid-1];
	int nhits_st1x;
	const gHits hits_st1x = hitcolls->hitschambers(blockIdx.x, globalconsts::eff_detid_chambers[detid-1], nhits_st1x);
	const float z_st1x = planes->z[detid];
	const float res_st1x = planes->resolution[detid];
	
	detid-= 1;
	detid_list[1] = globalconsts::eff_detid_chambers[detid-1];
	int nhits_st1xp;
	const gHits hits_st1xp = hitcolls->hitschambers(blockIdx.x, globalconsts::eff_detid_chambers[detid-1], nhits_st1xp);
	const float z_st1xp = planes->z[detid];
	const float res_st1xp = planes->resolution[detid];

	projid = 1;
	detid = globalconsts::detsuperid[stid][projid]*2;
	detid_list[2] = globalconsts::eff_detid_chambers[detid-1];
	int nhits_st1u;
	const gHits hits_st1u = hitcolls->hitschambers(blockIdx.x, globalconsts::eff_detid_chambers[detid-1], nhits_st1u);
	const float z_st1u = planes->z[detid];
	const float res_st1u = planes->resolution[detid];
	
	detid-= 1;
	detid_list[3] = globalconsts::eff_detid_chambers[detid-1];
	int nhits_st1up;
	const gHits hits_st1up = hitcolls->hitschambers(blockIdx.x, globalconsts::eff_detid_chambers[detid-1], nhits_st1up);
	const float z_st1up = planes->z[detid];
	const float res_st1up = planes->resolution[detid];
	
	projid = 2;
	detid = globalconsts::detsuperid[stid][projid]*2;
	detid_list[4] = globalconsts::eff_detid_chambers[detid-1];
	int nhits_st1v;
	const gHits hits_st1v = hitcolls->hitschambers(blockIdx.x, globalconsts::eff_detid_chambers[detid-1], nhits_st1v);
	const float z_st1v = planes->z[detid];
	const float res_st1v = planes->resolution[detid];
	
	detid-= 1;
	detid_list[5] = globalconsts::eff_detid_chambers[detid-1];
	int nhits_st1vp;
	const gHits hits_st1vp = hitcolls->hitschambers(blockIdx.x, globalconsts::eff_detid_chambers[detid-1], nhits_st1vp);
	const float z_st1vp = planes->z[detid];
	const float res_st1vp = planes->resolution[detid];

	// TODO: load the hodoscope hits
	stid = 0;//1-1
	detid = globalconsts::hodoplanesx[stid][0];
	int nhits_h1x1;
	const gHits hits_h1x1 = hitcolls->hitshodos(blockIdx.x, detid, nhits_h1x1);
#ifdef DEBUG
	if(blockIdx.x==debug::EvRef && threadIdx.x==0){printf("nhits h1x1 %d \n", nhits_h1x1);
	for(int l = 0; l<nhits_h1x1; l++)printf("det %d chan %1.0f pos %1.4f \n", detid, hits_h1x1.chan(l), hits_h1x1.pos(l));
	}
#endif
	detid = globalconsts::hodoplanesx[stid][1];
	int nhits_h1x2;
	const gHits hits_h1x2 = hitcolls->hitshodos(blockIdx.x, detid, nhits_h1x2);
#ifdef DEBUG
	if(blockIdx.x==debug::EvRef && threadIdx.x==0){printf("nhits h1x2 %d \n", nhits_h1x2);
	for(int l = 0; l<nhits_h1x2; l++)printf("det %d chan %1.0f pos %1.4f \n", detid, hits_h1x2.chan(l), hits_h1x2.pos(l));
	}
#endif
	
#ifdef HODO_Y_MATCH
	detid = globalconsts::hodoplanesy[stid][0];
	int nhits_h1y1;
	const gHits hits_h1y1 = hitcolls->hitshodos(blockIdx.x, detid, nhits_h1y1);
#ifdef DEBUG
	if(blockIdx.x==debug::EvRef && threadIdx.x==0){printf("nhits h1y1 %d \n", nhits_h1y1);
	for(int l = 0; l<nhits_h1y1; l++)printf("det %d chan %1.0f pos %1.4f \n", detid, hits_h1y1.chan(l), hits_h1y1.pos(l));
	}
#endif

	detid = globalconsts::hodoplanesy[stid][1];
	int nhits_h1y2;
	const gHits hits_h1y2 = hitcolls->hitshodos(blockIdx.x, detid, nhits_h1y2);
#ifdef DEBUG
	if(blockIdx.x==debug::EvRef && threadIdx.x==0){printf("nhits h1y2 %d \n", nhits_h1y2);
	for(int l = 0; l<nhits_h1y2; l++)printf("det %d chan %1.0f pos %1.4f \n", detid, hits_h1y2.chan(l), hits_h1y2.pos(l));
	}
#endif
#endif	
	bool maskhodo;
	
	//Sagitta ratio
	float pos_exp[3];
	float window[3];
	
	//full track calculation
	float x0_st1, tx_st1;
	float errx0_st1, errtx_st1;

	float x0, tx;
	float errx0, errtx;
	float y0, ty;
	float erry0, errty;
	
	float invP, errinvP;
	short charge;
#ifdef TEST_MOMENTUM
	float tx_tgt, invp_tgt;
#endif
	bool update_track;
	short nhits_st23, nhits_st1;
	
	//variables for the loop
	int i_x, i_u, i_v, i_uv;
	int ncomb_uv;
	int nhits_x, nhits_u, nhits_v, nhits_uv;
	int i_hit;
	
	//variables for 2D track fit
	short detID[18];
	short elID[18];
	float pos[18];
	float drift[18];
	float tdc[18];
	short sign[18];
	
	float Y[18];
	float errY[18];
	float Z_[18];
	short nyhits = 0;
	
	float X[3];
	float errX[3];
	float Z[3];
	
	float y, err_y;
	float y0_prev, ty_prev;
			
	float A_[4];
	float Ainv_[4];
	float B_[2];
	float Par[2];
	float ParErr[2];
	float chi2;	
	
	float res[18];
	float dd[18];
	float hs[18];
	float p1x[18];
	float p1y[18];
	float p1z[18];
	float dpx[18];
	float dpy[18];
	float dpz[18];
	float residuals[18];
	
	short detid_st23[12];
	short chan_st23[12];
	float drift_st23[12];
	short sign_st23[12];
	float residuals_st23[12];
	float resolution_st23[12];
	
	float chi2min = 10000.1f;

	//get the tracks...
	const unsigned int tkl_coll_offset = blockIdx.x*datasizes::TrackSizeMax*datasizes::NTracksParam;
	const unsigned int array_thread_offset = threadIdx.x*datasizes::TrackSizeMax*datasizes::NTracksParam/THREADS_PER_BLOCK;
	
	__shared__ float besttrackdata[THREADS_PER_BLOCK][datasizes::NTracksParam];
	
	unsigned int Ntracks;
	const gTracks Tracks = tklcoll->tracks(blockIdx.x, threadIdx.x, Ntracks);
	
	for(int i = 0; i<Ntracks; i++){
		//tkl = Tracks.getTracklet(i);
		update_track = false;
		nhits_st23 = Tracks.nHits(i);
		
		if(Tracks.stationID(i)<5)continue;
		chi2min = 10000.1f;
		
		x0 = Tracks.x0(i);
		tx = Tracks.tx(i);
		errx0 = Tracks.err_x0(i);
		errtx = Tracks.err_tx(i);

		y0 = Tracks.y0(i);
		ty = Tracks.ty(i);
		erry0 = Tracks.err_y0(i);
		errty = Tracks.err_ty(i);
		
		SagittaRatioInStation1(x0, tx, y0, ty, Tracks.get_lasthitdetid(i, planes->z), pos_exp, window, planes->z, planes->costheta, planes->sintheta);
		
		projid = 0;
		nx1 = make_hitpairs_in_station(hits_st1x, nhits_st1x, hits_st1xp, nhits_st1xp, hitpairs_x1, hitidx1, hitidx2, hitflag1, hitflag2, stid, projid, planes, pos_exp[projid]-window[projid]*1.0f, pos_exp[projid]+window[projid]*1.0f);
		
		projid = 1;
		nu1 = make_hitpairs_in_station(hits_st1u, nhits_st1u, hits_st1up, nhits_st1up, hitpairs_u1, hitidx1, hitidx2, hitflag1, hitflag2, stid, projid, planes, pos_exp[projid]-window[projid]*1.0f, pos_exp[projid]+window[projid]*1.0f);
		
		projid = 2;
		nv1 = make_hitpairs_in_station(hits_st1v, nhits_st1v, hits_st1vp, nhits_st1vp, hitpairs_v1, hitidx1, hitidx2, hitflag1, hitflag2, stid, projid, planes, pos_exp[projid]-window[projid]*1.0f, pos_exp[projid]+window[projid]*1.0f);

#ifdef DEBUG
		if(blockIdx.x==debug::EvRef){
			printf("GT: thread %d i_trk %d x0 %1.4f y0 %1.4f tx %1.4f ty %1.4f nhits %1.0f detid %d, nx1 %d nu1 %d nv1 %d \n", threadIdx.x, i, x0, y0, tx, ty, Tracks.nHits(i), Tracks.get_lasthitdetid(i, planes->z), nx1, nu1, nv1);
			for(int ll=0; ll<3; ll++)printf(" thread %d ll %d pos %1.4f window %1.4f  =>  %1.4f < %1.4f \n ", threadIdx.x, ll, pos_exp[ll], window[ll], pos_exp[ll]-window[ll], pos_exp[ll]+window[ll]);
		}
#endif
		
		if(nx1==0 || nu1==0 || nv1==0)continue;
		
		nyhits = 0;
		for(int k = 0; k<nhits_st23; k++){
			detid_st23[k] = Tracks.hits_detid(i, k); 
			chan_st23[k] = Tracks.hits_chan(i, k);
			drift_st23[k] = Tracks.hits_drift(i, k);
			sign_st23[k] = Tracks.hits_sign(i, k);
			resolution_st23[k] = planes->resolution[(short)Tracks.hits_detid(i, k)];
			
			if(planes->costheta[(short)Tracks.hits_detid(i, k)]>0.99)continue;
			
			if(calculate_y_uvhit(Tracks.hits_detid(i, k), Tracks.hits_chan(i, k), Tracks.hits_drift(i, k), Tracks.hits_sign(i, k), x0, tx, planes, y, err_y)){
				Y[nyhits] = y;
				errY[nyhits] = err_y;
				Z_[nyhits] = planes->z[(short)Tracks.hits_detid(i, k)];
				nyhits++;
			}
		}
		
		ncomb_uv = nu1*nv1;
		
		//triple loop on hits
		for(i_x = 0; i_x<nx1; i_x++){
			nhits_x = 0;
			if(hitpairs_x1[i_x].first>=0){
				detID[nhits_x] = detid_list[0];
				i_hit = hitpairs_x1[i_x].first;
				//X[nhits_x] = hits_st1x.pos(i_hit);
				pos[nhits_x] = hits_st1x.pos(i_hit);
				errX[nhits_x] = res_st1x;
				//Z[nhits_x] = z_st1x;
				elID[nhits_x] = (short)hits_st1x.chan(i_hit);
				tdc[nhits_x] = hits_st1x.tdc(i_hit);
				sign[nhits_x] = 0;
				drift[nhits_x] = hits_st1x.drift(i_hit);
				calculate_xz_fy(detID[nhits_x], elID[nhits_x], drift[nhits_x], sign[nhits_x], y0, ty, planes, X[nhits_x], Z[nhits_x]);
				
#ifdef DEBUG
				if(blockIdx.x==debug::EvRef)printf("thread %d i_trk %d det %d chan %d pos %1.4f drift %1.4f\n", threadIdx.x, i, detID[nhits_x], elID[nhits_x], pos[nhits_x], drift[nhits_x]);
#endif
				res[nhits_x] = planes->resolution[detID[nhits_x]];
				p1x[nhits_x] = x_bep(detID[nhits_x], elID[nhits_x], planes);
				p1y[nhits_x] = y_bep(detID[nhits_x], elID[nhits_x], planes);
				p1z[nhits_x] = z_bep(detID[nhits_x], elID[nhits_x], planes);
				dpx[nhits_x] = planes->deltapx[detID[nhits_x]];
				dpy[nhits_x] = planes->deltapy[detID[nhits_x]];
				dpz[nhits_x] = planes->deltapz[detID[nhits_x]];
				
				nhits_x++;
			}
			if(hitpairs_x1[i_x].second>=0){
				detID[nhits_x] = detid_list[1];
				i_hit = hitpairs_x1[i_x].second;
				//X[nhits_x] = hits_st1xp.pos(i_hit);
				pos[nhits_x] = hits_st1xp.pos(i_hit);
				errX[nhits_x] = res_st1xp;
				//Z[nhits_x] = z_st1xp;
				elID[nhits_x] = (short)hits_st1xp.chan(i_hit);
				tdc[nhits_x] = hits_st1xp.tdc(i_hit);
				sign[nhits_x] = 0;
				drift[nhits_x] = hits_st1xp.drift(i_hit);
				calculate_xz_fy(detID[nhits_x], elID[nhits_x], drift[nhits_x], sign[nhits_x], y0, ty, planes, X[nhits_x], Z[nhits_x]);
#ifdef DEBUG
				if(blockIdx.x==debug::EvRef)printf("thread %d i_trk %d det %d chan %d pos %1.4f drift %1.4f\n", threadIdx.x, i, detID[nhits_x], elID[nhits_x], pos[nhits_x], drift[nhits_x]);
#endif
				res[nhits_x] = planes->resolution[detID[nhits_x]];
				p1x[nhits_x] = x_bep(detID[nhits_x], elID[nhits_x], planes);
				p1y[nhits_x] = y_bep(detID[nhits_x], elID[nhits_x], planes);
				p1z[nhits_x] = z_bep(detID[nhits_x], elID[nhits_x], planes);
				dpx[nhits_x] = planes->deltapx[detID[nhits_x]];
				dpy[nhits_x] = planes->deltapy[detID[nhits_x]];
				dpz[nhits_x] = planes->deltapz[detID[nhits_x]];
				
				nhits_x++;
			}
						
			if(nhits_x==0) continue;
			
			X[nhits_x] = x0+tx*globalconsts::Z_KMAG_BEND;
			errX[nhits_x] = errx0+errtx*globalconsts::Z_KMAG_BEND;
			Z[nhits_x] = globalconsts::Z_KMAG_BEND;

#ifdef DEBUG
			if(blockIdx.x==debug::EvRef)printf("x0 %1.4f y0 %1.4f tx %1.4f ty %1.4f nhits x %d first hit det %d chan %d pos %1.4f last hit det %d chan %d pos %1.4f, zmag x pos %1.4f \n", x0, y0, tx, ty, nhits_x, detID[0], elID[0], X[0], detID[nhits_x-1], elID[nhits_x-1], X[nhits_x-1], X[nhits_x]);
#endif
			
			fit_2D_track(nhits_x+1, X, Z, errX, A_, Ainv_, B_, Par, ParErr, chi2);
			x0_st1 = Par[0];
			tx_st1 = Par[1];

			errx0_st1 = Par[0];
			errtx_st1 = Par[1];

			resolve_leftright_xhits(x0_st1, tx_st1, errx0_st1, errtx_st1, nhits_x, detID, X, drift, sign, planes->z, 150.);
			resolve_single_leftright_xhits(x0_st1, tx_st1, nhits_x, detID, X, sign, planes->z);
			
			for(short l = 0; l<nhits_x; l++){
#ifdef DEBUG
				if(blockIdx.x==debug::EvRef)printf("l %d hit sign %d drift %1.4f \n", l, sign[l], drift[l]);
#endif
				X[l]+= sign[l]*drift[l];
			}
			fit_2D_track(nhits_x+1, X, Z, errX, A_, Ainv_, B_, Par, ParErr, chi2);
#ifdef DEBUG
			if(blockIdx.x==debug::EvRef)printf("before: x0 %1.4f, tx %1.4f, after: x0 %1.4f tx %1.4f \n", x0_st1, tx_st1, Par[0], Par[1]);
#endif
			x0_st1 = Par[0];
			tx_st1 = Par[1];

			errx0_st1 = Par[0];
			errtx_st1 = Par[1];
			
			
			charge = calculate_charge(tx, x0);
			invP = calculate_invP(tx, tx_st1, charge);
			//invP = calculate_invP_charge(tx, tx_st1, charge);
			errinvP = calculate_invP_error(errtx, errtx_st1);
						
			if(invP>INVP_MAX+errinvP || invP<INVP_MIN-errinvP)continue;
			
#ifdef TEST_MOMENTUM
			tx_tgt = x_trk(x0_st1, tx_st1, globalconsts::Z_FMAG_BEND)/(globalconsts::Z_FMAG_BEND-globalconsts::Z_TARGET);
			invp_tgt = calculate_invp_tgt(tx_st1, tx_tgt, charge);
#endif
								
#ifdef DEBUG
			if(blockIdx.x==debug::EvRef)printf("thread %d x0 %1.4f y0 %1.4f tx %1.4f ty %1.4f invP %1.4f x0_st1 %1.4f tx_st1 %1.4f charge %d nhits x %d first hit det %d chan %d last hit det %d chan %d \n", threadIdx.x, x0, y0, tx, ty, invP, x0_st1, tx_st1, charge, nhits_x, detID[0], elID[0], detID[nhits_x-1], elID[nhits_x-1]);
#endif

							
			//add the UV hits
			for(i_uv = 0; i_uv<ncomb_uv; i_uv++){
				i_u = i_uv%nu1;
				i_v = (i_uv-i_u)/nu1;
				
				nhits_uv = 0;
				if(hitpairs_u1[i_u].first>=0){
					detID[nhits_x+nhits_uv] = detid_list[2];
					i_hit = hitpairs_u1[i_u].first;
					elID[nhits_x+nhits_uv] = (short)hits_st1u.chan(i_hit);
					tdc[nhits_x+nhits_uv] = hits_st1u.tdc(i_hit);
					sign[nhits_x+nhits_uv] = 0;
					drift[nhits_x+nhits_uv] = hits_st1u.drift(i_hit);
					pos[nhits_x+nhits_uv] = hits_st1u.pos(i_hit);
#ifdef DEBUG
					if(blockIdx.x==debug::EvRef)printf("det %d chan %d pos %1.4f drift %1.4f\n", detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], pos[nhits_x+nhits_uv], drift[nhits_x+nhits_uv]);
#endif

					if(calculate_y_uvhit(detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], drift[nhits_x+nhits_uv], 0, x0_st1, tx_st1, planes, y, err_y)){
#ifdef DEBUG
						if(blockIdx.x==debug::EvRef){
							printf("thread %d i_trk %d det %d chan %d pos %1.4f drift %1.4f\n", threadIdx.x, i, detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], pos[nhits_x+nhits_uv], drift[nhits_x+nhits_uv]);
						}
#endif
						//if( (y-y_trk(y0, ty, z_st1u))*(y-y_trk(y0, ty, z_st1u)) / (err_y*err_y+err_y_trk(erry0, errty, z_st1u)*err_y_trk(erry0, errty, z_st1u))<=12.0f ){
							res[nhits_x+nhits_uv] = planes->resolution[detID[nhits_x+nhits_uv]];
							p1x[nhits_x+nhits_uv] = x_bep(detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], planes);
							p1y[nhits_x+nhits_uv] = y_bep(detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], planes);
							p1z[nhits_x+nhits_uv] = z_bep(detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], planes);
							dpx[nhits_x+nhits_uv] = planes->deltapx[detID[nhits_x+nhits_uv]];
							dpy[nhits_x+nhits_uv] = planes->deltapy[detID[nhits_x+nhits_uv]];
							dpz[nhits_x+nhits_uv] = planes->deltapz[detID[nhits_x+nhits_uv]];

							Y[nyhits+nhits_uv] = y;
							errY[nyhits+nhits_uv] = err_y;
							Z_[nyhits+nhits_uv] = z_st1u;
							
							nhits_uv++;
						//}
					}
				}
				if(hitpairs_u1[i_u].second>=0){
					detID[nhits_x+nhits_uv] = detid_list[3];
					i_hit = hitpairs_u1[i_u].second;
					elID[nhits_x+nhits_uv] = (short)hits_st1up.chan(i_hit);
					tdc[nhits_x+nhits_uv] = hits_st1up.tdc(i_hit);
					sign[nhits_x+nhits_uv] = 0;
					drift[nhits_x+nhits_uv] = hits_st1up.drift(i_hit);
					pos[nhits_x+nhits_uv] = hits_st1up.pos(i_hit);
#ifdef DEBUG
					if(blockIdx.x==debug::EvRef)printf("det %d chan %d pos %1.4f drift %1.4f\n", detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], pos[nhits_x+nhits_uv], drift[nhits_x+nhits_uv]);
#endif
					if(calculate_y_uvhit(detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], drift[nhits_x+nhits_uv], 0, x0_st1, tx_st1, planes, y, err_y)){
#ifdef DEBUG
						if(blockIdx.x==debug::EvRef){
							printf("thread %d i_trk %d det %d chan %d pos %1.4f drift %1.4f\n", threadIdx.x, i, detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], pos[nhits_x+nhits_uv], drift[nhits_x+nhits_uv]);
						}
#endif
						//if( (y-y_trk(y0, ty, z_st1up))*(y-y_trk(y0, ty, z_st1up))/(err_y*err_y+err_y_trk(erry0, errty, z_st1up)*err_y_trk(erry0, errty, z_st1up))<=12.0f ){
							res[nhits_x+nhits_uv] = planes->resolution[detID[nhits_x+nhits_uv]];
							p1x[nhits_x+nhits_uv] = x_bep(detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], planes);
							p1y[nhits_x+nhits_uv] = y_bep(detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], planes);
							p1z[nhits_x+nhits_uv] = z_bep(detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], planes);
							dpx[nhits_x+nhits_uv] = planes->deltapx[detID[nhits_x+nhits_uv]];
							dpy[nhits_x+nhits_uv] = planes->deltapy[detID[nhits_x+nhits_uv]];
							dpz[nhits_x+nhits_uv] = planes->deltapz[detID[nhits_x+nhits_uv]];

							Y[nyhits+nhits_uv] = y;
							errY[nyhits+nhits_uv] = err_y;
							Z_[nyhits+nhits_uv] = z_st1up;
							
							nhits_uv++;
						//}
					}
				}
				nhits_u = nhits_uv;
				
				if(nhits_u==0)continue;
				
				if(hitpairs_v1[i_v].first>=0){
					detID[nhits_x+nhits_uv] = detid_list[4];
					i_hit = hitpairs_v1[i_v].first;
					elID[nhits_x+nhits_uv] = (short)hits_st1v.chan(i_hit);
					tdc[nhits_x+nhits_uv] = hits_st1v.tdc(i_hit);
					sign[nhits_x+nhits_uv] = 0;
					drift[nhits_x+nhits_uv] = hits_st1v.drift(i_hit);
					pos[nhits_x+nhits_uv] = hits_st1v.pos(i_hit);
#ifdef DEBUG
					if(blockIdx.x==debug::EvRef)printf("det %d chan %d pos %1.4f drift %1.4f\n", detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], pos[nhits_x+nhits_uv], drift[nhits_x+nhits_uv]);
#endif
					if(calculate_y_uvhit(detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], drift[nhits_x+nhits_uv], 0, x0_st1, tx_st1, planes, y, err_y)){
#ifdef DEBUG
						if(blockIdx.x==debug::EvRef){
							printf("thread %d i_trk %d det %d chan %d pos %1.4f drift %1.4f\n", threadIdx.x, i, detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], pos[nhits_x+nhits_uv], drift[nhits_x+nhits_uv]);
						}
#endif
						//if( (y-y_trk(y0, ty, z_st1v))*(y-y_trk(y0, ty, z_st1v))/(err_y*err_y+err_y_trk(erry0, errty, z_st1v)*err_y_trk(erry0, errty, z_st1v))<=12.0f ){
							res[nhits_x+nhits_uv] = planes->resolution[detID[nhits_x+nhits_uv]];
							p1x[nhits_x+nhits_uv] = x_bep(detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], planes);
							p1y[nhits_x+nhits_uv] = y_bep(detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], planes);
							p1z[nhits_x+nhits_uv] = z_bep(detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], planes);
							dpx[nhits_x+nhits_uv] = planes->deltapx[detID[nhits_x+nhits_uv]];
							dpy[nhits_x+nhits_uv] = planes->deltapy[detID[nhits_x+nhits_uv]];
							dpz[nhits_x+nhits_uv] = planes->deltapz[detID[nhits_x+nhits_uv]];

							Y[nyhits+nhits_uv] = y;
							errY[nyhits+nhits_uv] = err_y;
							Z_[nyhits+nhits_uv] = z_st1v;
							
							nhits_uv++;
						//}
					}
				}
				if(hitpairs_v1[i_v].second>=0){
					detID[nhits_x+nhits_uv] = detid_list[5];
					i_hit = hitpairs_v1[i_v].second;
					elID[nhits_x+nhits_uv] = (short)hits_st1vp.chan(i_hit);
					tdc[nhits_x+nhits_uv] = hits_st1vp.tdc(i_hit);
					sign[nhits_x+nhits_uv] = 0;
					drift[nhits_x+nhits_uv] = hits_st1vp.drift(i_hit);
					pos[nhits_x+nhits_uv] = hits_st1vp.pos(i_hit);
#ifdef DEBUG
					if(blockIdx.x==debug::EvRef)printf("det %d chan %d pos %1.4f drift %1.4f\n", detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], pos[nhits_x+nhits_uv], drift[nhits_x+nhits_uv]);
#endif
					if(calculate_y_uvhit(detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], drift[nhits_x+nhits_uv], 0, x0_st1, tx_st1, planes, y, err_y)){
#ifdef DEBUG
						if(blockIdx.x==debug::EvRef){
							if(blockIdx.x==debug::EvRef)printf(" thread %d i_trk %d det %d chan %d pos %1.4f drift %1.4f\n", threadIdx.x, i, detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], pos[nhits_x+nhits_uv], drift[nhits_x+nhits_uv]);
						}
#endif
						//if( (y-y_trk(y0, ty, z_st1vp))*(y-y_trk(y0, ty, z_st1vp))/(err_y*err_y+err_y_trk(erry0, errty, z_st1vp)*err_y_trk(erry0, errty, z_st1vp))<=12.0f ){
							res[nhits_x+nhits_uv] = planes->resolution[detID[nhits_x+nhits_uv]];
							p1x[nhits_x+nhits_uv] = x_bep(detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], planes);
							p1y[nhits_x+nhits_uv] = y_bep(detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], planes);
							p1z[nhits_x+nhits_uv] = z_bep(detID[nhits_x+nhits_uv], elID[nhits_x+nhits_uv], planes);
							dpx[nhits_x+nhits_uv] = planes->deltapx[detID[nhits_x+nhits_uv]];
							dpy[nhits_x+nhits_uv] = planes->deltapy[detID[nhits_x+nhits_uv]];
							dpz[nhits_x+nhits_uv] = planes->deltapz[detID[nhits_x+nhits_uv]];

							Y[nyhits+nhits_uv] = y;
							errY[nyhits+nhits_uv] = err_y;
							Z_[nyhits+nhits_uv] = z_st1vp;
							
							nhits_uv++;
						//}
					}
				}
				nhits_v = nhits_uv-nhits_u;
#ifdef DEBUG
				if(blockIdx.x==debug::EvRef)printf("x0 %1.4f y0 %1.4f tx %1.4f ty %1.4f invP %1.4f nhits uv %d first hit det %d chan %d last hit det %d chan %d \n", x0, y0, tx, ty, invP, nhits_uv, detID[nhits_x+nhits_u], elID[nhits_x+nhits_u], detID[nhits_x+nhits_uv-1], elID[nhits_x+nhits_uv-1]);
#endif
				if(nhits_v==0)continue;

				fit_2D_track(nyhits+nhits_uv, Y, Z_, errY, A_, Ainv_, B_, Par, ParErr, chi2);

				y0_prev = y0;
				ty_prev = ty;
				
				y0 = Par[0];
				ty = Par[1];

				erry0 = ParErr[0];
				errty = ParErr[1];
				
				if(fabs(y0)>Y0_MAX+2*erry0 || fabs(ty)>TY_MAX+2*errty)continue;

				//resolve left right...
				resolve_leftright_newhits(x0_st1, tx_st1, y0, ty, errx0_st1, errtx_st1, erry0, errty, nhits_x+nhits_uv, detID, pos, drift, sign, planes, 150.);
				resolve_single_leftright_newhits(x0_st1, tx_st1, y0, ty, nhits_x+nhits_uv, detID, pos, sign, planes);

#ifdef DEBUG				
				if(blockIdx.x==debug::EvRef){
					printf("GT thread %d combi %d-%d-%d \n", threadIdx.x, i_x, i_u, i_v);				
				}
				
				for(int ll = 0; ll<nhits_x; ll++){
					if(blockIdx.x==debug::EvRef)printf(" thread %d hit %d det %d chan %d Z %1.4f pos %1.4f ;\n", threadIdx.x, ll, detID[ll], elID[ll], Z[ll], pos[ll]);
				}
				for(int ll = 0; ll<nhits_uv; ll++){
					if(blockIdx.x==debug::EvRef)printf(" thread %d hit %d det %d chan %d Z %1.4f Y %1.4f ;\n", threadIdx.x, ll, detID[nhits_x+ll], elID[nhits_x+ll], Z_[nyhits+ll], Y[nyhits+ll]);
					//Y[nyhits+ll]+= sign[ll]*drift[ll]*planes->sintheta[detID[ll]];
				}
#endif
				fit_2D_track(nyhits+nhits_uv, Y, Z_, errY, A_, Ainv_, B_, Par, ParErr, chi2);
				
#ifdef DEBUG				
				if(blockIdx.x==debug::EvRef)printf("thread %d GT: y0 %1.4f ty %1.4f, invP %1.4f \n", threadIdx.x, Par[0], Par[1], invP);	
#endif				
				
				y0 = Par[0];
				ty = Par[1];

				erry0 = ParErr[0];
				errty = ParErr[1];
				
				if(fabs(y0)>Y0_MAX || fabs(ty)>TY_MAX)continue;
				
				//check for 
				//if(!check_target_pointing_quick(x0, tx, y0, ty, invP, charge))continue;
				
				// matching hodoscope here!
				stid = 0;//1-1
				maskhodo = 0;
				detid = globalconsts::hodoplanesx[stid][0];

#ifdef DEBUG
				if(blockIdx.x==debug::EvRef)printf(" evt %d x0_st1 %1.4f +- %1.4f tx_st1 %1.4f +- %1.4f y0 %1.4f +- %1.4f ty %1.4f +- %1.4f invP %1.4f +- %1.4f \n", blockIdx.x, x0_st1, errx0_st1, tx_st1, errtx_st1, y0, erry0, ty, errty, invP, errinvP);
#endif

				maskhodo = match_tracklet_to_hodo(stid, detid, nhits_h1x1, hits_h1x1, x0_st1, y0, tx_st1, ty, errx0_st1, erry0, errtx_st1, errty, planes);
				if(!maskhodo){
					detid = globalconsts::hodoplanesx[stid][1];
					maskhodo = maskhodo || match_tracklet_to_hodo(stid, detid, nhits_h1x2, hits_h1x2, x0_st1, y0, tx_st1, ty, errx0_st1, erry0, errtx_st1, errty, planes);
				}
	
#ifdef HODO_Y_MATCH
				if(!maskhodo){
					detid = globalconsts::hodoplanesy[stid][0];
					maskhodo = match_tracklet_to_hodo(stid, detid, nhits_h1y1, hits_h1y1, x0_st1, y0, tx_st1, ty, errx0_st1, erry0, errtx_st1, errty, planes);
					if(!maskhodo){
						detid = globalconsts::hodoplanesy[stid][1];
						maskhodo = maskhodo || match_tracklet_to_hodo(stid, detid, nhits_h1y2, hits_h1y2, x0_st1, y0, tx_st1, ty, errx0_st1, erry0, errtx_st1, errty, planes);
					}
				}
				if(!maskhodo)continue;
#endif
				
#ifdef DEBUG
				if(blockIdx.x==debug::EvRef)printf(" x0_st1 %1.4f tx_st1 %1.4f y0 %1.4f ty %1.4f \n", x0_st1, tx_st1, y0, ty);
#endif

				//TODO: rematch hodo, prop tubes!
				
				//update residuals, chi2
				chi2 = 0;
				for(short mm = 0; mm<nhits_st23; mm++){
					residuals_st23[mm] = residual(detid_st23[mm], chan_st23[mm], drift_st23[mm], sign_st23[mm], planes, x0, y0, tx, ty);
					chi2+= residuals_st23[mm]*residuals_st23[mm]/(resolution_st23[mm]*resolution_st23[mm]);
				}
				
#ifdef DEBUG
				if(blockIdx.x==debug::EvRef)printf("GT: thread %d combi %d-%d-%d, chi2 %1.4f \n", threadIdx.x, i_x, i_u, i_v, chi2);
#endif

				//chi2 fit...
				chi2+= chi2_track(nhits_x+nhits_uv, residuals, drift, sign, res, p1x, p1y, p1z, dpx, dpy, dpz, x0_st1, y0, tx_st1, ty);
				if(chi2>10000.f)continue;
				
#ifdef DEBUG
				printf(" %d %d %1.6f %1.6f %1.6f %1.6f %1.6f %1.6f %1.6f %1.6f \n", blockIdx.x, threadIdx.x, x0, tx, invP, y0, ty, y0_prev, ty_prev, chi2);
#endif
				
#ifdef DEBUG
				if(blockIdx.x==debug::EvRef)printf("GT: thread %d combi %d-%d-%d, chi2 %1.4f \n", threadIdx.x, i_x, i_u, i_v, chi2);
#endif				
				if(chi2<chi2min){
					chi2min = chi2;
					update_track = true;
					besttrackdata[threadIdx.x][2] = nhits_x+nhits_uv;
					besttrackdata[threadIdx.x][3] = chi2;
					besttrackdata[threadIdx.x][6] = ty;
					besttrackdata[threadIdx.x][8] = y0;
					besttrackdata[threadIdx.x][9] = invP;
					besttrackdata[threadIdx.x][11] = errty;
					besttrackdata[threadIdx.x][13] = erry0;
					besttrackdata[threadIdx.x][14] = errinvP;
					besttrackdata[threadIdx.x][15] = charge;
#ifdef TEST_MOMENTUM
					besttrackdata[threadIdx.x][148] = invp_tgt;
#endif
					for(short m = 0; m<nhits_st23;m++){
						besttrackdata[threadIdx.x][124+m] = residuals_st23[m];
					}
					for(short m = 0; m<nhits_x+nhits_uv;m++){
						besttrackdata[threadIdx.x][16+m] = detID[m];
						besttrackdata[threadIdx.x][34+m] = elID[m];
						besttrackdata[threadIdx.x][52+m] = pos[m];
						besttrackdata[threadIdx.x][70+m] = drift[m];
						besttrackdata[threadIdx.x][88+m] = sign[m];
						besttrackdata[threadIdx.x][106+m] = tdc[m];
						besttrackdata[threadIdx.x][124+nhits_st23+m] = residuals[m];
					}
				}

				
			}
			
		}//end
		
		if(update_track){
			tklcoll->setStationID(tkl_coll_offset+array_thread_offset, i, 6);
			nhits_st1 = besttrackdata[threadIdx.x][2];
			tklcoll->setnHits(tkl_coll_offset+array_thread_offset, i, nhits_st23+besttrackdata[threadIdx.x][2]);
			tklcoll->setChisq(tkl_coll_offset+array_thread_offset, i, besttrackdata[threadIdx.x][3]);
			tklcoll->setTy(tkl_coll_offset+array_thread_offset, i, besttrackdata[threadIdx.x][6]);
			tklcoll->setY0(tkl_coll_offset+array_thread_offset, i, besttrackdata[threadIdx.x][8]);
			tklcoll->setinvP(tkl_coll_offset+array_thread_offset, i, besttrackdata[threadIdx.x][9]);
			tklcoll->setErrTy(tkl_coll_offset+array_thread_offset, i, besttrackdata[threadIdx.x][11]);
			tklcoll->setErrY0(tkl_coll_offset+array_thread_offset, i, besttrackdata[threadIdx.x][13]);
			tklcoll->setErrinvP(tkl_coll_offset+array_thread_offset, i, besttrackdata[threadIdx.x][14]);
			tklcoll->setCharge(tkl_coll_offset+array_thread_offset, i, besttrackdata[threadIdx.x][15]);

			for(int n = 0; n<nhits_st23; n++){
				tklcoll->setHitResidual(tkl_coll_offset+array_thread_offset, i, n, besttrackdata[threadIdx.x][124+n]);
			}
			for(int n = 0; n<nhits_st1; n++){
				tklcoll->setHitDetID(tkl_coll_offset+array_thread_offset, i, nhits_st23+n, besttrackdata[threadIdx.x][16+n]);
				tklcoll->setHitChan(tkl_coll_offset+array_thread_offset, i, nhits_st23+n, besttrackdata[threadIdx.x][34+n]);
				tklcoll->setHitPos(tkl_coll_offset+array_thread_offset, i, nhits_st23+n, besttrackdata[threadIdx.x][52+n]);
				tklcoll->setHitDrift(tkl_coll_offset+array_thread_offset, i, nhits_st23+n, besttrackdata[threadIdx.x][70+n]);
				tklcoll->setHitSign(tkl_coll_offset+array_thread_offset, i, nhits_st23+n, besttrackdata[threadIdx.x][88+n]);
				tklcoll->setHitTDC(tkl_coll_offset+array_thread_offset, i, nhits_st23+n, besttrackdata[threadIdx.x][106+n]);
				tklcoll->setHitResidual(tkl_coll_offset+array_thread_offset, i, nhits_st23+n, besttrackdata[threadIdx.x][124+nhits_st23+n]);
			}
#ifdef TEST_MOMENTUM
			tklcoll->setInvPTarget(tkl_coll_offset+array_thread_offset, i, besttrackdata[threadIdx.x][148]);
#endif
		}
	}//end tracklets loop
}

// --------------- //
//
// Track vertexing 
//
// --------------- //

__global__ void gKernel_Vertexing(
	gEventTrackCollection* tklcoll,
	const float* z_array,
#ifdef DEBUG
	int* eventID,
#endif
	bool* hastoomanyhits)
{
	if(hastoomanyhits[blockIdx.x]){
#ifdef DEBUG
		if(threadIdx.x==0)printf("Evt %d discarded, too many hits\n", eventID[blockIdx.x]);
#endif
		return;
	}
	
	const unsigned int tkl_coll_offset = blockIdx.x*datasizes::TrackSizeMax*datasizes::NTracksParam;
	const unsigned int array_thread_offset = threadIdx.x*datasizes::TrackSizeMax*datasizes::NTracksParam/THREADS_PER_BLOCK;
	
	unsigned int Ntracks;
	const gTracks Tracks = tklcoll->tracks(blockIdx.x, threadIdx.x, Ntracks);
	
	short detid_first;
	
	double z_0;
	double state_0[5];
	//double cov_mat_0[25];
	
	double tx_i, tx_f;
	double ptot_i, ptot_b, ptot_f;
	double pz_0, pz_f;
	double traj1[3];
	double traj2[3];
	double pos_b[3];
	
	float x0, tx, x0_st1, tx_st1, y0, ty, invP, charge;
	
	int ix, iy, iz;
	int ix_m1, iy_m1, iz_m1;

	double pos_array[3*(globalconsts::NSTEPS_FMAG+globalconsts::NSTEPS_TARGET+1)];
	double mom_array[3*(globalconsts::NSTEPS_FMAG+globalconsts::NSTEPS_TARGET+1)];
	
	double dz;
	int step, step_x, step_y;
	
	double dca2_min, dca_xmin, dca_ymin;
	double dca2, dca_x, dca_y;

	//"output" observables	
	double dump_pos[3];
	double dump_mom[3];
	
	float vertex_pos[3];
	float vertex_mom[3];
	
	for(int i = 0; i<Ntracks; i++){
		if(Tracks.stationID(i)<6)continue;
		
		x0 = Tracks.x0(i);
		y0 = Tracks.y0(i);
		tx = Tracks.tx(i);
		ty = Tracks.ty(i);
		invP = Tracks.invP(i); 
		charge = Tracks.charge(i); 
		detid_first = Tracks.get_firsthitdetid(i, z_array);
		
		calculate_x0_tx_st1(x0, tx, invP, charge, x0_st1, tx_st1);
		
		z_0 = z_array[detid_first];
		
		state_0[0] = charge*invP*sqrtf(  (1.f+tx_st1*tx_st1)/(1.f+tx_st1*tx_st1+ty*ty) );
		state_0[1] = tx_st1;
		state_0[2] = ty;
		state_0[3] = x_trk(x0_st1, tx_st1, z_0);
		state_0[4] = y_trk(y0, ty, z_0);
		
#ifdef DEBUG
		if(blockIdx.x==debug::EvRef){
			printf("invP %1.8f num %1.8f den %1.8f sqrt %1.8f ", invP, (1.f+tx_st1*tx_st1), (1.f+tx_st1*tx_st1+ty*ty), sqrtf(  (1.f+tx_st1*tx_st1)/(1.f+tx_st1*tx_st1+ty*ty) ) );
			printf("front state %1.8f %1.8f %1.8f %1.8f %1.8f, %d z_0 =  %1.8f \n", state_0[0], state_0[1], state_0[2], state_0[3], state_0[4], detid_first, z_0);
		}
#endif
		
		pos_array[0] = state_0[3]+state_0[1]*(globalconsts::FMAG_LENGTH-z_0);
		pos_array[1] = state_0[4]+state_0[2]*(globalconsts::FMAG_LENGTH-z_0);
		pos_array[2] = globalconsts::FMAG_LENGTH;
		
		pz_0 = 1.f/( fabs(state_0[0]) * sqrtf(1.f + state_0[1]*state_0[1] + state_0[2]*state_0[2]) );
		
		mom_array[0] = pz_0*state_0[1];
		mom_array[1] = pz_0*state_0[2];
		mom_array[2] = pz_0;
		
		if(pz_0<0)if(blockIdx.x==debug::EvRef)printf("%d %d mom %1.6f %1.6f %1.6f pos %1.6f %1.6f %1.6f \n", blockIdx.x, threadIdx.x, mom_array[0], mom_array[1], mom_array[2], pos_array[0], pos_array[1], pos_array[2]);
		
#ifdef DEBUG
		if(blockIdx.x==debug::EvRef)printf(" FMAG_LENGTH-z_0 %1.4f pos(0) %1.4f %1.4f %1.4f  mom(0) %1.4f %1.4f %1.4f \n", globalconsts::FMAG_LENGTH-z_0, pos_array[0], pos_array[1], pos_array[2], mom_array[0], mom_array[1], mom_array[2] );
		if(blockIdx.x==debug::EvRef)printf("charge %1.0f\n", charge);
#endif

		step = 1;
		for(; step <= globalconsts::NSTEPS_FMAG; ++step){
			ix = step*3;
			iy = step*3+1;
			iz = step*3+2;
			ix_m1 = (step-1)*3;
			iy_m1 = (step-1)*3+1;
			iz_m1 = (step-1)*3+2;
			
			tx_i = mom_array[ix_m1]/mom_array[iz_m1];
			tx_f = tx_i + 2.f*charge*globalconsts::PTKICK_UNIT*globalconsts::STEP_FMAG/sqrt(mom_array[ix_m1]*mom_array[ix_m1]+mom_array[iz_m1]*mom_array[iz_m1]);
#ifdef DEBUG
			if(blockIdx.x==debug::EvRef)printf("step %d, tx_i = %1.8f, tx_f = %1.8f, PTKICK_UNIT %1.8f, charge %1.0f, sqrt %1.8f \n", step, tx_i, tx_f, globalconsts::PTKICK_UNIT, charge, sqrt(mom_array[ix_m1]*mom_array[ix_m1]+mom_array[iz_m1]*mom_array[iz_m1]));
#endif
			
			traj1[0] = tx_i*globalconsts::STEP_FMAG;
			traj1[1] = ty*globalconsts::STEP_FMAG;
			traj1[2] = globalconsts::STEP_FMAG;
			
			pos_b[0] = pos_array[ix_m1]-traj1[0];
			pos_b[1] = pos_array[iy_m1]-traj1[1];
			pos_b[2] = pos_array[iz_m1]-traj1[2];
			
			ptot_i = sqrt(mom_array[ix_m1]*mom_array[ix_m1]+mom_array[iy_m1]*mom_array[iy_m1]+mom_array[iz_m1]*mom_array[iz_m1]);
			ptot_b = ptot_i;
			if(pos_b[2] > globalconsts::FMAG_HOLE_LENGTH || pos_b[0]*pos_b[0]+pos_b[1]*pos_b[1]>globalconsts::FMAG_HOLE_RADIUS){
				ptot_b+= (globalconsts::DEDX_UNIT_0 + globalconsts::DEDX_UNIT_1*ptot_i + globalconsts::DEDX_UNIT_2*ptot_i*ptot_i + globalconsts::DEDX_UNIT_3*ptot_i*ptot_i*ptot_i + globalconsts::DEDX_UNIT_4*ptot_i*ptot_i*ptot_i*ptot_i)*sqrtf( traj1[0]*traj1[0] + traj1[1]*traj1[1] + traj1[2]*traj1[2]);
			}
			
			traj2[0] = tx_f*globalconsts::STEP_FMAG;
			traj2[1] = ty*globalconsts::STEP_FMAG;
			traj2[2] = globalconsts::STEP_FMAG;
			
			pos_array[ix] = pos_b[0]-traj2[0];
			pos_array[iy] = pos_b[1]-traj2[1];
			pos_array[iz] = pos_b[2]-traj2[2];
			
			ptot_f = ptot_b;
			if(pos_array[iz] > globalconsts::FMAG_HOLE_LENGTH || pos_array[ix]*pos_array[ix]+pos_array[iy]*pos_array[iy]>globalconsts::FMAG_HOLE_RADIUS){
				ptot_f+= (globalconsts::DEDX_UNIT_0 + globalconsts::DEDX_UNIT_1*ptot_b + globalconsts::DEDX_UNIT_2*ptot_b*ptot_b + globalconsts::DEDX_UNIT_3*ptot_b*ptot_b*ptot_b + globalconsts::DEDX_UNIT_4*ptot_b*ptot_b*ptot_b*ptot_b)*sqrtf( traj2[0]*traj2[0] + traj2[1]*traj2[1] + traj2[2]*traj2[2]);
			}
			
			pz_f = ptot_f/sqrt(1.f+tx_f*tx_f+ty*ty);

			mom_array[ix] = pz_f*tx_f;
			mom_array[iy] = pz_f*ty;
			mom_array[iz] = pz_f;
			
#ifdef DEBUG
			if(blockIdx.x==debug::EvRef){
				//printf(" ptoti %1.4f ptotb %1.4f ptotf %1.4f traj1 %1.4f %1.4f %1.4f traj2 %1.4f %1.4f %1.4f \n", ptot_i, ptot_b, ptot_f, traj1[0], traj1[1], traj1[2], traj2[0], traj2[1], traj2[2]);
				printf("%d %d %d %d %1.4f %1.4f %1.4f %1.4f %1.4f %1.4f \n", step, ix, iy, iz, pos_array[ix], pos_array[iy], pos_array[iz], mom_array[ix], mom_array[iy], mom_array[iz] );
			}
#endif

			dz = pos_b[2] - globalconsts::Z_DUMP;
			if(fabs(dz)<globalconsts::STEP_FMAG){
				if(dz<0){
					dump_pos[0] = pos_b[0]+dz*tx_f;
					dump_pos[1] = pos_b[1]+dz*ty;
					dump_pos[2] = pos_b[2]+dz;

					dump_mom[0] = mom_array[ix];
					dump_mom[1] = mom_array[iy];
					dump_mom[2] = mom_array[iz];
				}else{
					dump_pos[0] = pos_b[0]+dz*tx_i;
					dump_pos[1] = pos_b[1]+dz*ty;
					dump_pos[2] = pos_b[2]+dz;
					
					dump_mom[0] = mom_array[ix_m1];
					dump_mom[1] = mom_array[iy_m1];
					dump_mom[2] = mom_array[iz_m1];
				}
			}
		}//end loop on FMAG steps
		
		for(; step<=globalconsts::NSTEPS_FMAG+globalconsts::NSTEPS_TARGET; ++step){
			ix = step*3;
			iy = step*3+1;
			iz = step*3+2;
			ix_m1 = (step-1)*3;
			iy_m1 = (step-1)*3+1;
			iz_m1 = (step-1)*3+2;

			tx_i = mom_array[ix_m1]/mom_array[iz_m1];

			traj1[0] = tx_i*globalconsts::STEP_TARGET;
			traj1[1] = ty*globalconsts::STEP_TARGET;
			traj1[2] = globalconsts::STEP_TARGET;

			mom_array[ix] = mom_array[ix_m1];
			mom_array[iy] = mom_array[iy_m1];
			mom_array[iz] = mom_array[iz_m1];
			
			pos_array[ix] = pos_array[ix_m1]-traj1[0];
			pos_array[iy] = pos_array[iy_m1]-traj1[1];
			pos_array[iz] = pos_array[iz_m1]-traj1[2];
#ifdef DEBUG
			if(blockIdx.x==debug::EvRef)printf("%d %d %d %d %1.6f %1.6f %1.6f %1.6f %1.6f %1.6f \n", step, ix, iy, iz, pos_array[ix], pos_array[iy], pos_array[iz], mom_array[ix], mom_array[iy], mom_array[iz] );
#endif
		}//end loop on TARGET steps
#ifdef DEBUG
		if(mom_array[2]!=pz_0)printf("%d %d\n", blockIdx.x, threadIdx.x);
#endif
		
		//now?
		dca2_min = 1.e18;
		dca_xmin = 1.e9;
		dca_ymin = 1.e9;
		
		step = globalconsts::NSTEPS_FMAG+globalconsts::NSTEPS_TARGET;
		step_x = step;
		step_y = step;
		
		for(int j = 0; j<=globalconsts::NSTEPS_FMAG+globalconsts::NSTEPS_TARGET; j++){
			ix = j*3;
			iy = j*3+1;
			iz = j*3+2;
			if(globalconsts::FMAGSTR*charge*mom_array[ix] < 0.) continue;
			
			dca2 = (pos_array[ix]-globalconsts::X_BEAM)*(pos_array[ix]-globalconsts::X_BEAM) + (pos_array[iy]-globalconsts::Y_BEAM)*(pos_array[iy]-globalconsts::Y_BEAM);

			if(dca2<dca2_min){
				dca2_min  =  dca2;
				step = j;
			}
			
			dca_x = fabs(pos_array[ix]-globalconsts::X_BEAM);
			if(dca_xmin>dca_x){
				dca_xmin  =  dca_x;
				step_x = j;
			}
			
			dca_y = fabs(pos_array[iy]-globalconsts::Y_BEAM);
			if(dca_ymin>dca_y){
				dca_ymin  =  dca_y;
				step_y = j;
			}
#ifdef DEBUG
			if(blockIdx.x==debug::EvRef)printf("%d %d %d %1.6f %1.6f %1.6f %1.6f %1.6f %1.6f %1.6f %1.6f %1.6f \n", ix, iy, iz, pos_array[ix], pos_array[iy], pos_array[iz], mom_array[ix], mom_array[iy], mom_array[iz], dca2, dca_x, dca_y );
#endif
		}
		
		ix = step*3;
		iy = step*3+1;
		iz = step*3+2;
		
		vertex_pos[0] = pos_array[ix];
		vertex_pos[1] = pos_array[iy];
		vertex_pos[2] = pos_array[iz];
		
		vertex_mom[0] = mom_array[ix];
		vertex_mom[1] = mom_array[iy];
		vertex_mom[2] = mom_array[iz];
		
#ifdef DEBUG
		if(blockIdx.x==debug::EvRef)printf("%d %d  %d  %1.6f %1.6f %1.6f %1.6f %1.6f %1.6f %1.6f \n", blockIdx.x, threadIdx.x, step, pos_array[ix], pos_array[iy], pos_array[iz], mom_array[ix], mom_array[iy], mom_array[iz], dca2_min);
#endif
		tklcoll->setStationID(tkl_coll_offset+array_thread_offset, i, 7);//vertexing has been done...

		tklcoll->setVtxPos(tkl_coll_offset+array_thread_offset, i, vertex_pos);
		tklcoll->setVtxMom(tkl_coll_offset+array_thread_offset, i, vertex_mom);
		
		
	}//end loop on tracks
	
	
}


// --------------------------------------------- //
//
// dimuon building kernel
// 
// --------------------------------------------- //


__global__ void gKernel_DimuonBuilding(
	gEventTrackCollection* tklcoll,
	gEventDimuonCollection* dimcoll,
	const float* z_array,
#ifdef DEBUG
	int* eventID,
#endif
	const bool* hastoomanyhits)
{
	if(hastoomanyhits[blockIdx.x])return;
	//const unsigned int tkl_coll_offset = blockIdx.x*datasizes::TrackSizeMax*datasizes::NTracksParam;
	const unsigned int dim_coll_offset = blockIdx.x*datasizes::DimuonSizeMax*datasizes::NDimuonParam;

	const float p_beam[4] = {0, 0, kinematics::Pbeam, kinematics::Ebeam};
	const float p_target[4] = {0, 0, 0, kinematics::Mp};
	const float p_cms[4] = {0, 0, kinematics::Pbeam, kinematics::Ebeam+kinematics::Mp};
	
	const float s = M2(p_cms);
#ifdef DEBUG
	if(blockIdx.x==debug::EvRef)printf("s = %1.4f, = %1.4f \n", s, 2.0f*kinematics::Mp*(kinematics::Mp + kinematics::Ebeam) );
#endif
	const float sqrt_s = sqrtf(s);
	//const float cms_bv_z = p_cms[2]/p_cms[3];//p_cms[0]/p_cms[3] = p_cms[1]/p_cms[3] = 0  
	const float cms_bv[3] = {0.0, 0.0, p_cms[2]/p_cms[3]};//p_cms[0]/p_cms[3] = p_cms[1]/p_cms[3] = 0  
	//const float beta2 = cms_bv_z*cms_bv_z;
	//const float gamma = 1.f/sqrtf(1.f-beta2);
		
	float p_pos[4];
	float p_neg[4];
	
	float p_pos_single[4];
	float p_neg_single[4];
	
	// two hypotheses for vertex: first is average of two vertices, second is distance of closest approach between both tracks
	float vz_1, vz_2;
	float v_1[3], v_2[3];
	float dim_v[3];
	float pos_v[3];
	float neg_v[3];
		
	float p_sum[4];
	
	float m, x1, x2, xF, pT, costheta, phi;
	float m_single, chi2_single, chi2_vtx, chi2_kf;
	
	//Loop on all track threads, then loop on all tracks in each thread
	int i_trd, j_trd;
	int i_trk, j_trk;
	
	unsigned int Ntracks_i, Ntracks_j;
	//unsigned int array_thread_offset[THREADS_PER_BLOCK];

	short detid_first;
	float z_0, pz_0, x0, tx, x0_st1, tx_st1, y0, ty_1, ty_2, invP, charge_1, charge_2;
	float state_0[5];

	float pos_array_1[3*(globalconsts::NSTEPS_FMAG+globalconsts::NSTEPS_TARGET+1)];
	float mom_array_1[3*(globalconsts::NSTEPS_FMAG+globalconsts::NSTEPS_TARGET+1)];
	float pos_array_2[3*(globalconsts::NSTEPS_FMAG+globalconsts::NSTEPS_TARGET+1)];
	float mom_array_2[3*(globalconsts::NSTEPS_FMAG+globalconsts::NSTEPS_TARGET+1)];

	
	//for(i_trd = 0; i_trd<THREADS_PER_BLOCK; i_trd++){
	//	//Tracks[i_trd] = tklcoll->tracks(blockIdx.x, i_trd, Ntracks[i_trd]);
	//	array_thread_offset[i_trd] = i_trd*datasizes::TrackSizeMax*datasizes::NTracksParam/THREADS_PER_BLOCK;
	//}		

	int ndim = 0;

	for(i_trd = 0; i_trd<THREADS_PER_BLOCK; i_trd++){
		gTracks Tracks_i = tklcoll->tracks(blockIdx.x, i_trd, Ntracks_i);
		
		for(j_trd = i_trd; j_trd<THREADS_PER_BLOCK; j_trd++){
			gTracks Tracks_j = tklcoll->tracks(blockIdx.x, j_trd, Ntracks_j);
			
			for(i_trk = 0; i_trk<Ntracks_i; i_trk++){
				if(Tracks_i.stationID(i_trk)<7)continue;
				//if(Tracks_i.chisq(i_trk)>selection::chi2max)continue;
				
				if(Tracks_i.charge(i_trk)>0){
					p_pos[0] = Tracks_i.px(i_trk);
					p_pos[1] = Tracks_i.py(i_trk);
					p_pos[2] = Tracks_i.pz(i_trk);
					p_pos[3] = E(kinematics::Mmu, p_pos);
										
					pos_v[0] = Tracks_i.vx(i_trk);
					pos_v[1] = Tracks_i.vy(i_trk);
					pos_v[2] = Tracks_i.vz(i_trk);
				}else{
					p_neg[0] = Tracks_i.px(i_trk);
					p_neg[1] = Tracks_i.py(i_trk);
					p_neg[2] = Tracks_i.pz(i_trk);
					p_neg[3] = E(kinematics::Mmu, p_neg);
					
					neg_v[0] = Tracks_i.vx(i_trk);
					neg_v[1] = Tracks_i.vy(i_trk);
					neg_v[2] = Tracks_i.vz(i_trk);
				}
				for(j_trk = 0; j_trk<Ntracks_j; j_trk++){
					if(Tracks_j.stationID(j_trk)<7)continue;
					//if(Tracks_j.chisq(j_trk)>selection::chi2max)continue;
					if(Tracks_j.charge(j_trk)*Tracks_i.charge(i_trk)>0)continue;

					//if(fabs(Tracks_j.vz(j_trk)-Tracks_i.vz(i_trk))>250.)continue;

					if(Tracks_j.charge(j_trk)>0){
						p_pos[0] = Tracks_j.px(j_trk);
						p_pos[1] = Tracks_j.py(j_trk);
						p_pos[2] = Tracks_j.pz(j_trk);
						p_pos[3] = E(kinematics::Mmu, p_pos);
						
						pos_v[0] = Tracks_j.vx(j_trk);
						pos_v[1] = Tracks_j.vy(j_trk);
						pos_v[2] = Tracks_j.vz(j_trk);
					}else{
						p_neg[0] = Tracks_j.px(j_trk);
						p_neg[1] = Tracks_j.py(j_trk);
						p_neg[2] = Tracks_j.pz(j_trk);
						p_neg[3] = E(kinematics::Mmu, p_neg);
						
						neg_v[0] = Tracks_j.vx(j_trk);
						neg_v[1] = Tracks_j.vy(j_trk);
						neg_v[2] = Tracks_j.vz(j_trk);
					}
					copy4vec(p_pos_single, p_pos);
					copy4vec(p_neg_single, p_neg);
					
					sum3vec(v_1, pos_v, neg_v);
					for(short k = 0; k<3; k++)v_1[k]*= 0.5f;
					vz_1 = v_1[2];
					
					//get second vertex:
					x0 = Tracks_i.x0(i_trk);
					y0 = Tracks_i.y0(i_trk);
					tx = Tracks_i.tx(i_trk);
					ty_1 = Tracks_i.ty(i_trk);
					invP = Tracks_i.invP(i_trk); 
					charge_1 = Tracks_i.charge(i_trk); 
					detid_first = Tracks_i.get_firsthitdetid(i_trk, z_array);
					
					calculate_x0_tx_st1(x0, tx, invP, charge_1, x0_st1, tx_st1);
					
					z_0 = z_array[detid_first];
							
					state_0[0] = charge_1*invP*sqrtf(  (1.f+tx_st1*tx_st1)/(1.f+tx_st1*tx_st1+ty_1*ty_1) );
					state_0[1] = tx_st1;
					state_0[2] = ty_1;
					state_0[3] = x_trk(x0_st1, tx_st1, z_0);
					state_0[4] = y_trk(y0, ty_1, z_0);

					pos_array_1[0] = state_0[3]+state_0[1]*(globalconsts::FMAG_LENGTH-z_0);
					pos_array_1[1] = state_0[4]+state_0[2]*(globalconsts::FMAG_LENGTH-z_0);
					pos_array_1[2] = globalconsts::FMAG_LENGTH;
					
					pz_0 = 1.f/( fabs(state_0[0]) * sqrtf(1.f + state_0[1]*state_0[1] + state_0[2]*state_0[2]) );
					
					mom_array_1[0] = pz_0*state_0[1];
					mom_array_1[1] = pz_0*state_0[2];
					mom_array_1[2] = pz_0;
					
					x0 = Tracks_j.x0(j_trk);
					y0 = Tracks_j.y0(j_trk);
					tx = Tracks_j.tx(j_trk);
					ty_2 = Tracks_j.ty(j_trk);
					invP = Tracks_j.invP(j_trk); 
					charge_2 = Tracks_j.charge(j_trk); 
					detid_first = Tracks_j.get_firsthitdetid(j_trk, z_array);
					
					calculate_x0_tx_st1(x0, tx, invP, charge_2, x0_st1, tx_st1);
					
					z_0 = z_array[detid_first];

					state_0[0] = charge_2*invP*sqrtf(  (1.f+tx_st1*tx_st1)/(1.f+tx_st1*tx_st1+ty_2*ty_2) );
					state_0[1] = tx_st1;
					state_0[2] = ty_2;
					state_0[3] = x_trk(x0_st1, tx_st1, z_0);
					state_0[4] = y_trk(y0, ty_2, z_0);
							
					pos_array_2[0] = state_0[3]+state_0[1]*(globalconsts::FMAG_LENGTH-z_0);
					pos_array_2[1] = state_0[4]+state_0[2]*(globalconsts::FMAG_LENGTH-z_0);
					pos_array_2[2] = globalconsts::FMAG_LENGTH;
					
					pz_0 = 1.f/( fabs(state_0[0]) * sqrtf(1.f + state_0[1]*state_0[1] + state_0[2]*state_0[2]) );
					
					mom_array_2[0] = pz_0*state_0[1];
					mom_array_2[1] = pz_0*state_0[2];
					mom_array_2[2] = pz_0;
					
					vz_2 = FindDimuonClosestApproach(v_2, p_pos, p_neg, charge_1, charge_2, ty_1, ty_2, pos_array_1, mom_array_1, pos_array_2, mom_array_2);
					p_pos[3] = E(kinematics::Mmu, p_pos);
					p_neg[3] = E(kinematics::Mmu, p_neg);
					
					if(fabs(vz_2-v_2[2])<globalconsts::STEP_FMAG){
						sum4vec(p_sum, p_pos, p_neg);
						dim_v[0] = v_2[0];
						dim_v[1] = v_2[1];
						dim_v[2] = v_2[2];
					}else{
						sum4vec(p_sum, p_pos_single, p_neg_single);
						dim_v[0] = v_1[0];
						dim_v[1] = v_1[1];
						dim_v[2] = v_1[2];
					}
					
					
					// get the variables
					m = M(p_sum);
					pT = Perp(p_sum);
					x1 = mult4vec(p_target, p_sum)/mult4vec(p_target, p_cms);
					x2 = mult4vec(p_beam, p_sum)/mult4vec(p_beam, p_cms);
					
#ifdef DEBUG
					if(blockIdx.x==debug::EvRef)printf(" p_sum_z = %1.4f, boost_z = %1.4f \n", p_sum[2], cms_bv[2] );
#endif
					Boost(p_sum, cms_bv, -1);
					xF = 2.0f*p_sum[2]/(sqrt_s*(1.f - m*m/s));
#ifdef DEBUG
					if(blockIdx.x==debug::EvRef)printf(" p_sum_z = %1.4f, s = %1.4f sqrt s = %1.4f, m = %1.4f, dimu_pl_max %1.4f \n", p_sum[2], s, sqrt_s, m, sqrt_s*(1.f - m*m/s)*0.5f );
#endif
					
					costheta = 2* (p_neg[3]*p_pos[2]-p_neg[2]*p_pos[3])/(m * sqrtf(m*m + pT*pT));
					phi = atan2f( 2*sqrtf(m*m + pT*pT)*(p_neg[0]*p_pos[1]-p_neg[1]*p_pos[0]) , m*(p_pos[0]*p_pos[0] - p_neg[0]*p_neg[0] + p_pos[1]*p_pos[1] - p_neg[1]*p_neg[1] ) );
					
					//filter
					if(globalconsts::FMAGSTR*(p_pos[0] - p_neg[0]) < 0.)continue;
					if(m<0 || m>10.f)continue;
					if(fabs(xF)>1.f)continue;
					if(x1<0.f || x1>1.f)continue;
					if(x2<0.f || x2>1.f)continue;
					if(fabs(costheta)>1.f)continue;
					if(p_pos[2]+p_neg[2]>120.f || p_pos[2]+p_neg[2]<30.f)continue;
					if(fabs(p_pos[0]+p_neg[0])>3.f || fabs(p_pos[0]+p_neg[0])>3.f )continue;
					//if(fabs(dim_v[0])>15.f || fabs(dim_v[1])>15.f )continue;
					if(dim_v[0]*dim_v[0]+dim_v[1]*dim_v[1]>225.f )continue;
					//if(dim_v[2]>200. || dim_v[2]<-300.)continue;

					//printf(" evt %d dim v %1.4f %1.4f %1.4f pos v %1.4f %1.4f %1.4f neg v %1.4f %1.4f %1.4f \n", blockIdx.x, dim_v[0], dim_v[1], dim_v[2], pos_v[0], pos_v[1], pos_v[2], neg_v[0], neg_v[1], neg_v[2] );
					
					//Fill information in array
					if(ndim>datasizes::DimuonSizeMax){
						printf(" block %d ndim %d \n ", blockIdx.x, ndim);
						continue;
					}
					dimcoll->setMass(dim_coll_offset, ndim, m);
					dimcoll->setpT(dim_coll_offset, ndim, pT);
					dimcoll->setxF(dim_coll_offset, ndim, xF);
					dimcoll->setx1(dim_coll_offset, ndim, x1);
					dimcoll->setx2(dim_coll_offset, ndim, x2);
					dimcoll->setcostheta(dim_coll_offset, ndim, costheta);
					dimcoll->setphi(dim_coll_offset, ndim, phi);
					dimcoll->setMassSingle(dim_coll_offset, ndim, m_single);
					dimcoll->setChi2Single(dim_coll_offset, ndim, chi2_single);

					dimcoll->setDimVtx(dim_coll_offset, ndim, dim_v);
					dimcoll->setPosVtx(dim_coll_offset, ndim, pos_v);
					dimcoll->setNegVtx(dim_coll_offset, ndim, neg_v);
					
					dimcoll->setPos4Vector(dim_coll_offset, ndim, p_pos);
					dimcoll->setNeg4Vector(dim_coll_offset, ndim, p_neg);
					dimcoll->setPosSingle4Vector(dim_coll_offset, ndim, p_pos_single);
					dimcoll->setNegSingle4Vector(dim_coll_offset, ndim, p_neg_single);
					
					dimcoll->setChi2Vtx(dim_coll_offset, ndim, chi2_vtx);
					dimcoll->setChi2Vtx(dim_coll_offset, ndim, chi2_kf);
					ndim++;
				}
			}
		}
	}
	dimcoll->NDimuons[blockIdx.x] = ndim;
}




// --------------------------------------------- //
//
// function to fill the "histograms"/arrays to be displayed
// 
// --------------------------------------------- //
__global__ void gKernel_fill_display_histograms(gEventTrackCollection* tklcoll, gEventDimuonCollection* dimcoll, gHistsArrays* HistsArrays, const int* TriggerBits, const bool* hastoomanyhits)
{
	if(hastoomanyhits[blockIdx.x])return;
	
	bool trig_array[histotools::ntriggers];
	
	short ntrg;
	for(ntrg = 0; ntrg<histotools::ntriggers; ntrg++){
		trig_array[ntrg] = TriggerBits[blockIdx.x] & ntrg;
	}
	trig_array[histotools::ntriggers-1] = true;//all triggers
	
	unsigned int nTracks, nDimuons;
	float vars[histotools::nvars_total];
	float x_hw, x;
	
	unsigned int bin;
	int i, j, k;
	
	//__shared__ float values_[NVars*Nbins_Hists];
	//for(j = 0; j<Nbins_Hists*NVars; j++)values_[j] = 0;
	
	for(int i_trd = 0; i_trd<THREADS_PER_BLOCK; i_trd++){
		const gTracks Tracks = tklcoll->tracks(blockIdx.x, i_trd, nTracks);
	
		for(i = 0; i<nTracks; i++){
			if(Tracks.stationID(i)<7 || Tracks.chisq(i)/(Tracks.nHits(i)-5)>selection::chi2dofmax)continue;// || Tracks.chisq(i)>100.f
			
			vars[0] = Tracks.px(i);
			vars[1] = Tracks.py(i);
			vars[2] = Tracks.pz(i);
			vars[3] = Tracks.vx(i);
			vars[4] = Tracks.vy(i);
			vars[5] = Tracks.vz(i);
			
			for(ntrg = 0; ntrg<histotools::ntriggers; ntrg++){
				if(!trig_array[ntrg])continue;
				
				for(k = 0; k<histotools::nvars_tracks; k++){
					for(j = 0; j<HistsArrays->nbins[ntrg*histotools::nvars_total+k]; j++){
						bin = ntrg*histotools::nvars_total*histotools::nbins_max+j+histotools::nbins_max*k;
						x_hw = HistsArrays->pts_hw[ntrg*histotools::nvars_total+k];
						x = HistsArrays->xpts[bin];
						if(x-x_hw<=vars[k] && vars[k]<x+x_hw){
							HistsArrays->values[bin]+=1.f;
							//values_[bin]+=1.f;
#ifdef DEBUG	
							if(k==2)printf(" bin %d  %1.4f < %1.4f < %1.4f : %1.4f; ", bin, x-x_hw, vars[k], x+x_hw, HistsArrays->values[bin]);
#endif
						}
					}
				}
			}
		}
	}
	
	const gDimuons dimuons = dimcoll->Dimuons(blockIdx.x, nDimuons);	
	for(i = 0; i<nDimuons; i++){
		vars[6] = dimuons.mass(i);
		vars[7] = dimuons.xF(i);
		vars[8] = dimuons.x1(i);
		vars[9] = dimuons.x2(i);
		vars[10] = dimuons.pT(i);
		vars[11] = dimuons.phi(i);
		vars[12] = dimuons.p_pos_x(i)+dimuons.p_neg_x(i);
		vars[13] = dimuons.p_pos_y(i)+dimuons.p_neg_y(i);
		vars[14] = dimuons.p_pos_z(i)+dimuons.p_neg_z(i);
		vars[15] = dimuons.dim_vx(i);
		vars[16] = dimuons.dim_vy(i);
		vars[17] = dimuons.dim_vz(i);
		
		for(ntrg = 0; ntrg<histotools::ntriggers; ntrg++){
			if(!trig_array[ntrg])continue;
		
			for(k = histotools::nvars_tracks; k<histotools::nvars_total; k++){
				x_hw = HistsArrays->pts_hw[ntrg*histotools::nvars_total+k];
				for(j = 0; j<HistsArrays->nbins[ntrg*histotools::nvars_total+k]; j++){
					bin = ntrg*histotools::nvars_total*histotools::nbins_max+j+histotools::nbins_max*k;
					x = HistsArrays->xpts[bin];
					if(x-x_hw<=vars[k] && vars[k]<x+x_hw){
						HistsArrays->values[bin]+=1.f;
						//values_[bin]+=1.f;
#ifdef DEBUG
						if(k==2)printf(" bin %d  %1.4f < %1.4f < %1.4f : %1.4f; ", bin, x-x_hw, vars[k], x+x_hw, HistsArrays->values[bin]);
#endif
					}
				}
			}
		}
	}
	__syncthreads();
	//cudaDeviceSynchronize();
	//for(j = 0; j<Nbins_Hists*NVars; j++){
	//	HistsArrays->values[j]+= values_[j];
	//}
}





#ifdef KALMAN_TRACKING


// ------------------------------
// Track Kalman fitting 
// ------------------------------

__global__ void gKernel_GlobalTrack_KalmanFitting(gOutputEvent* oc, gKalmanFitArrays* fitarrays, const gPlane* planes)
{
	int index = threadIdx.x + blockIdx.x * blockDim.x;
	
	if(oc[index].HasTooManyHits)return;
	
	int nhits_tkl;
	
	for(int k = 0; k<oc[index].nTracklets; k++){
		if(oc[index].AllTracklets[k].stationID<6)continue;
		
		nhits_tkl = oc[index].AllTracklets[k].nXHits+oc[index].AllTracklets[k].nUHits+oc[index].AllTracklets[k].nVHits;
		
		//initialize state
		//initialize_arrays(oc[index].AllTracklets[k], fitarrays[index]);
		
		
			if(oc[index].EventID<20)
		for(int i = 0; i<nhits_tkl; i++){
printf("hit %d, z = %1.3f \n", i, planes[oc[index].AllTracklets[k].hits[i].detectorID].z);
			// first predict the state at the hit z
			predict_state(oc[index].AllTracklets[k], planes[oc[index].AllTracklets[k].hits[i].detectorID].z, fitarrays[index]);
			update_state(oc[index].AllTracklets[k], oc[index].AllTracklets[k].hits[i], fitarrays[index], planes[oc[index].AllTracklets[k].hits[i].detectorID]);
		}
	}
	
	//
}


#endif





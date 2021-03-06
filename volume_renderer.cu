#include "stdio.h"
#include <stdlib.h>
#include "math.h"
#include <cuda_runtime.h>
#include <cuda.h>
#include "teem/nrrd.h"
#include "Image.h"
#include "sstream"

using namespace std;

#define PI 3.14159265


texture<short, 3, cudaReadModeNormalizedFloat> tex0;  // 3D texture
texture<short, 3, cudaReadModeNormalizedFloat> tex1;  // 3D texture
cudaArray *d_volumeArray0 = 0;
cudaArray *d_volumeArray1 = 0;

// w0, w1, w2, and w3 are the four cubic B-spline basis functions
__host__ __device__
float w0(float a)
{
    return (1.0f/6.0f)*(a*(a*(-a + 3.0f) - 3.0f) + 1.0f);
}

__host__ __device__
float w1(float a)
{
    return (1.0f/6.0f)*(a*a*(3.0f*a - 6.0f) + 4.0f);
}

__host__ __device__
float w2(float a)
{
    return (1.0f/6.0f)*(a*(a*(-3.0f*a + 3.0f) + 3.0f) + 1.0f);
}

__host__ __device__
float w3(float a)
{
    return (1.0f/6.0f)*(a*a*a);
}

//derivatives of basic functions
__host__ __device__
float w0g(float a)
{
    return -(1.0f/2.0f)*a*a + a - (1.0f/2.0f);
}

__host__ __device__
float w1g(float a)
{

    return (3.0f/2.0f)*a*a - 2*a;
}

__host__ __device__
float w2g(float a)
{
    return -(3.0f/2.0f)*a*a + a + (1.0/2.0);
}

__host__ __device__
float w3g(float a)
{
    return (1.0f/2.0f)*a*a;
}


// filter 4 values using cubic splines
template<class T>
__device__
T cubicFilter(float x, T c0, T c1, T c2, T c3)
{
    T r;
    r = c0 * w0(x);
    r += c1 * w1(x);
    r += c2 * w2(x);
    r += c3 * w3(x);
    return r;
}

//filtering with derivative of basic functions
template<class T>
__device__
T cubicFilter_G(float x, T c0, T c1, T c2, T c3)
{
    T r;
    r = c0 * w0g(x);
    r += c1 * w1g(x);
    r += c2 * w2g(x);
    r += c3 * w3g(x);
    return r;
}

template<class T, class R>  // texture data type, return type
__device__
R tex3DBicubicXY(const texture<T, 3, cudaReadModeNormalizedFloat> texref, float x, float y, float z)
{
    float px = floor(x);
    float py = floor(y);
    float fx = x - px;
    float fy = y - py;

    return cubicFilter<R>(fy,
                          cubicFilter<R>(fx, tex3D(texref, px-1, py-1,z), tex3D(texref, px, py-1,z), tex3D(texref, px+1, py-1,z), tex3D(texref, px+2,py-1,z)),
                          cubicFilter<R>(fx, tex3D(texref, px-1, py,z),   tex3D(texref, px, py,z),   tex3D(texref, px+1, py,z),   tex3D(texref, px+2, py,z)),
                          cubicFilter<R>(fx, tex3D(texref, px-1, py+1,z), tex3D(texref, px, py+1,z), tex3D(texref, px+1, py+1,z), tex3D(texref, px+2, py+1,z)),
                          cubicFilter<R>(fx, tex3D(texref, px-1, py+2,z), tex3D(texref, px, py+2,z), tex3D(texref, px+1, py+2,z), tex3D(texref, px+2, py+2,z))
                         );
}

//gradient in X direction
template<class T, class R>  // texture data type, return type
__device__
R tex3DBicubicXY_GX(const texture<T, 3, cudaReadModeNormalizedFloat> texref, float x, float y, float z)
{
    float px = floor(x);
    float py = floor(y);
    float fx = x - px;
    float fy = y - py;

    return cubicFilter<R>(fy,
                          cubicFilter_G<R>(fx, tex3D(texref, px-1, py-1,z), tex3D(texref, px, py-1,z), tex3D(texref, px+1, py-1,z), tex3D(texref, px+2,py-1,z)),
                          cubicFilter_G<R>(fx, tex3D(texref, px-1, py,z),   tex3D(texref, px, py,z),   tex3D(texref, px+1, py,z),   tex3D(texref, px+2, py,z)),
                          cubicFilter_G<R>(fx, tex3D(texref, px-1, py+1,z), tex3D(texref, px, py+1,z), tex3D(texref, px+1, py+1,z), tex3D(texref, px+2, py+1,z)),
                          cubicFilter_G<R>(fx, tex3D(texref, px-1, py+2,z), tex3D(texref, px, py+2,z), tex3D(texref, px+1, py+2,z), tex3D(texref, px+2, py+2,z))
                         );
}

template<class T, class R>  // texture data type, return type
__device__
R tex3DBicubicXY_GY(const texture<T, 3, cudaReadModeNormalizedFloat> texref, float x, float y, float z)
{
    float px = floor(x);
    float py = floor(y);
    float fx = x - px;
    float fy = y - py;

    return cubicFilter_G<R>(fy,
                          cubicFilter<R>(fx, tex3D(texref, px-1, py-1,z), tex3D(texref, px, py-1,z), tex3D(texref, px+1, py-1,z), tex3D(texref, px+2,py-1,z)),
                          cubicFilter<R>(fx, tex3D(texref, px-1, py,z),   tex3D(texref, px, py,z),   tex3D(texref, px+1, py,z),   tex3D(texref, px+2, py,z)),
                          cubicFilter<R>(fx, tex3D(texref, px-1, py+1,z), tex3D(texref, px, py+1,z), tex3D(texref, px+1, py+1,z), tex3D(texref, px+2, py+1,z)),
                          cubicFilter<R>(fx, tex3D(texref, px-1, py+2,z), tex3D(texref, px, py+2,z), tex3D(texref, px+1, py+2,z), tex3D(texref, px+2, py+2,z))
                         );
}

template<class T, class R>
__device__
R tex3DBicubic(const texture<T, 3, cudaReadModeNormalizedFloat> texref, float x, float y, float z)
{
    float pz = floor(z);
    float fz = z - pz;
    return cubicFilter<R>(fz,
                          tex3DBicubicXY<T,R>(texref,x,y,pz-1),
                          tex3DBicubicXY<T,R>(texref,x,y,pz),
                          tex3DBicubicXY<T,R>(texref,x,y,pz+1),
                          tex3DBicubicXY<T,R>(texref,x,y,pz+2)
                          );
}

template<class T, class R>
__device__
R tex3DBicubic_GX(const texture<T, 3, cudaReadModeNormalizedFloat> texref, float x, float y, float z)
{
    float pz = floor(z);
    float fz = z - pz;
    return cubicFilter<R>(fz,
                          tex3DBicubicXY_GX<T,R>(texref,x,y,pz-1),
                          tex3DBicubicXY_GX<T,R>(texref,x,y,pz),
                          tex3DBicubicXY_GX<T,R>(texref,x,y,pz+1),
                          tex3DBicubicXY_GX<T,R>(texref,x,y,pz+2)
                          );
}

template<class T, class R>
__device__
R tex3DBicubic_GY(const texture<T, 3, cudaReadModeNormalizedFloat> texref, float x, float y, float z)
{
    float pz = floor(z);
    float fz = z - pz;
    return cubicFilter<R>(fz,
                          tex3DBicubicXY_GY<T,R>(texref,x,y,pz-1),
                          tex3DBicubicXY_GY<T,R>(texref,x,y,pz),
                          tex3DBicubicXY_GY<T,R>(texref,x,y,pz+1),
                          tex3DBicubicXY_GY<T,R>(texref,x,y,pz+2)
                          );
}

template<class T, class R>
__device__
R tex3DBicubic_GZ(const texture<T, 3, cudaReadModeNormalizedFloat> texref, float x, float y, float z)
{
    float pz = floor(z);
    float fz = z - pz;
    return cubicFilter_G<R>(fz,
                            tex3DBicubicXY<T,R>(texref,x,y,pz-1),
                            tex3DBicubicXY<T,R>(texref,x,y,pz),
                            tex3DBicubicXY<T,R>(texref,x,y,pz+1),
                            tex3DBicubicXY<T,R>(texref,x,y,pz+2)
                            );
}

__host__ __device__
int cu_getIndex2(int i, int j, int s1, int s2)
{
    return i*s2+j;
}

__host__ __device__
double dotProduct(double *u, double *v, int s)
{
    double result = 0;
    for (int i=0; i<s; i++)
        result += (u[i]*v[i]);
    return result;
}

__host__ __device__
double lenVec(double *a, int s)
{
    double len = 0;
    for (int i=0; i<s; i++)
        len += (a[i]*a[i]);
    len = sqrt(len);
    return len;
}

void mulMatPoint(double X[4][4], double Y[4], double Z[4])
{
    for (int i=0; i<4; i++)
        Z[i] = 0;

    for (int i=0; i<4; i++)
        for (int k=0; k<4; k++)
            Z[i] += (X[i][k]*Y[k]);
}


__device__
void cu_mulMatPoint(double* X, double* Y, double* Z)
{
    for (int i=0; i<4; i++)
        Z[i] = 0;

    for (int i=0; i<4; i++)
        for (int k=0; k<4; k++)
            Z[i] += (X[cu_getIndex2(i,k,4,4)]*Y[k]);
}

__device__
void cu_mulMatPoint3(double* X, double* Y, double* Z)
{
    for (int i=0; i<3; i++)
        Z[i] = 0;

    for (int i=0; i<3; i++)
        for (int k=0; k<3; k++)
            Z[i] += (X[cu_getIndex2(i,k,3,3)]*Y[k]);
}

__host__ __device__
void advancePoint(double* point, double* dir, double scale, double* newpos)
{
    for (int i=0; i<3; i++)
        newpos[i] = point[i]+dir[i]*scale;
}

__device__
bool cu_isInsideDouble(double i, double j, double k, int dim1, int dim2, int dim3)
{
    return ((i>=0)&&(i<=(dim1-1))&&(j>=0)&&(j<=(dim2-1))&&(k>=0)&&(k<=(dim3-1)));
}

__device__
double cu_computeAlpha(double val, double grad_len, double isoval, double alphamax, double thickness)
{
    if ((grad_len == 0.0) && (val == isoval))
        return alphamax;
    else
        if ((grad_len>0.0) && (isoval >= (val-thickness*grad_len)) && (isoval <= (val+thickness*grad_len)))
            return alphamax*(1-abs(isoval-val)/(grad_len*thickness));
        else
            return 0.0;
}

__device__
double cu_inAlpha(double val, double grad_len, double isoval, double thickness)
{
    if (val >= isoval)
        return 1.0;
    else
    {
        return max(0.0,(1-abs(isoval-val)/(grad_len*thickness)));
    }
}

__host__ __device__
void normalize(double *a, int s)
{
    double len = lenVec(a,s);
    for (int i=0; i<s; i++)
        a[i] = a[i]/len;
}


__global__
void kernel(int* dim, int *size, double hor_extent, double ver_extent, double *center, double *viewdir, double *right, double *up, double *light_dir,
        double nc, double fc, double raystep, double refstep, double* mat_trans, double* mat_trans_inv, double* MT_BE_inv, double phongKa, double phongKd, double isoval, double alphamax, double thickness,
        int nOutChannel, double* imageDouble
        )
{
    int i = (blockIdx.x * blockDim.x) + threadIdx.x;
    int j = (blockIdx.y * blockDim.y) + threadIdx.y;

    if ((i>=size[0]) || (j>=size[1]))
        return;

    double hor_ratio = hor_extent/size[0];
    double ver_ratio = ver_extent/size[1];
    int ni = i-size[0]/2;
    int nj = size[1]/2 - j;

    double startPoint1[4];
    startPoint1[3] = 1;
    advancePoint(center,right,ni*ver_ratio,startPoint1);
    double startPoint2[4];
    startPoint2[3] = 1;
    advancePoint(startPoint1,up,nj*hor_ratio,startPoint2);

    memcpy(startPoint1,startPoint2,4*sizeof(double));

    double accColor = 0;
    double transp = 1;    
    double indPoint[4];
    double val;
    double gradi[3];
    double gradw[3];
    double gradw_len;
    //double gradi_len;
    double depth;
    double pointColor;
    double alpha;
    double mipVal = 0;
    double valgfp;

    for (double k=0; k<fc-nc; k+=raystep)
	{
        advancePoint(startPoint1,viewdir,raystep,startPoint2);

        cu_mulMatPoint(mat_trans_inv,startPoint1,indPoint);
        if (cu_isInsideDouble(indPoint[0],indPoint[1],indPoint[2],dim[1],dim[2],dim[3]))
		{

            val = tex3DBicubic<short,float>(tex1,indPoint[0],indPoint[1],indPoint[2]);
            
            gradi[0] = tex3DBicubic_GX<short,float>(tex1,indPoint[0],indPoint[1],indPoint[2]);
            gradi[1] = tex3DBicubic_GY<short,float>(tex1,indPoint[0],indPoint[1],indPoint[2]);
            gradi[2] = tex3DBicubic_GZ<short,float>(tex1,indPoint[0],indPoint[1],indPoint[2]);

            cu_mulMatPoint3(MT_BE_inv, gradi, gradw);
            gradw_len = lenVec(gradw,3);

            //negating and normalizing
            for (int l=0; l<3; l++)
                gradw[l] = -gradw[l]/gradw_len;

            depth = (k*1.0+1)/(fc*1.0-nc);

            pointColor = phongKa + depth*phongKd*max(0.0f,dotProduct(gradw,light_dir,3));
            alpha = cu_computeAlpha(val, gradw_len, isoval, alphamax, thickness);
            alpha = 1 - pow(1-alpha,raystep/refstep);
            transp *= (1-alpha);
            accColor = accColor*(1-alpha) + pointColor*alpha;

            valgfp = tex3DBicubic<short,float>(tex0,indPoint[0],indPoint[1],indPoint[2]);

            mipVal = max(mipVal,valgfp*cu_inAlpha(val,gradw_len,isoval,thickness));
		}

        memcpy(startPoint1,startPoint2,4*sizeof(double));
	}
    
    double accAlpha = 1 - transp;
    
    if (accAlpha>0)
    {        
        imageDouble[j*size[0]*nOutChannel+i*nOutChannel] = accColor/accAlpha;
        imageDouble[j*size[0]*nOutChannel+i*nOutChannel+1] = mipVal;
        imageDouble[j*size[0]*nOutChannel+i*nOutChannel+2] = 0;
    }
    else
    {        
        imageDouble[j*size[0]*nOutChannel+i*nOutChannel] = accColor;
        imageDouble[j*size[0]*nOutChannel+i*nOutChannel+1] = mipVal;
        imageDouble[j*size[0]*nOutChannel+i*nOutChannel+2] = 0;        
    }
    imageDouble[j*size[0]*nOutChannel+i*nOutChannel+nOutChannel-1] = accAlpha;    
}

double calDet44(double X[][4])
{
    double value = (
                    X[0][3]*X[1][2]*X[2][1]*X[3][0] - X[0][2]*X[1][3]*X[2][1]*X[3][0] - X[0][3]*X[1][1]*X[2][2]*X[3][0] + X[0][1]*X[1][3]*X[2][2]*X[3][0]+
                    X[0][2]*X[1][1]*X[2][3]*X[3][0] - X[0][1]*X[1][2]*X[2][3]*X[3][0] - X[0][3]*X[1][2]*X[2][0]*X[3][1] + X[0][2]*X[1][3]*X[2][0]*X[3][1]+
                    X[0][3]*X[1][0]*X[2][2]*X[3][1] - X[0][0]*X[1][3]*X[2][2]*X[3][1] - X[0][2]*X[1][0]*X[2][3]*X[3][1] + X[0][0]*X[1][2]*X[2][3]*X[3][1]+
                    X[0][3]*X[1][1]*X[2][0]*X[3][2] - X[0][1]*X[1][3]*X[2][0]*X[3][2] - X[0][3]*X[1][0]*X[2][1]*X[3][2] + X[0][0]*X[1][3]*X[2][1]*X[3][2]+
                    X[0][1]*X[1][0]*X[2][3]*X[3][2] - X[0][0]*X[1][1]*X[2][3]*X[3][2] - X[0][2]*X[1][1]*X[2][0]*X[3][3] + X[0][1]*X[1][2]*X[2][0]*X[3][3]+
                    X[0][2]*X[1][0]*X[2][1]*X[3][3] - X[0][0]*X[1][2]*X[2][1]*X[3][3] - X[0][1]*X[1][0]*X[2][2]*X[3][3] + X[0][0]*X[1][1]*X[2][2]*X[3][3]
                    );
    return value;
}

void invertMat44(double X[][4], double Y[][4])
{
    double det = calDet44(X);
    Y[0][0] = X[1][2]*X[2][3]*X[3][1] - X[1][3]*X[2][2]*X[3][1] + X[1][3]*X[2][1]*X[3][2] - X[1][1]*X[2][3]*X[3][2] - X[1][2]*X[2][1]*X[3][3] + X[1][1]*X[2][2]*X[3][3];
    Y[0][1] = X[0][3]*X[2][2]*X[3][1] - X[0][2]*X[2][3]*X[3][1] - X[0][3]*X[2][1]*X[3][2] + X[0][1]*X[2][3]*X[3][2] + X[0][2]*X[2][1]*X[3][3] - X[0][1]*X[2][2]*X[3][3];
    Y[0][2] = X[0][2]*X[1][3]*X[3][1] - X[0][3]*X[1][2]*X[3][1] + X[0][3]*X[1][1]*X[3][2] - X[0][1]*X[1][3]*X[3][2] - X[0][2]*X[1][1]*X[3][3] + X[0][1]*X[1][2]*X[3][3];
    Y[0][3] = X[0][3]*X[1][2]*X[2][1] - X[0][2]*X[1][3]*X[2][1] - X[0][3]*X[1][1]*X[2][2] + X[0][1]*X[1][3]*X[2][2] + X[0][2]*X[1][1]*X[2][3] - X[0][1]*X[1][2]*X[2][3];
    Y[1][0] = X[1][3]*X[2][2]*X[3][0] - X[1][2]*X[2][3]*X[3][0] - X[1][3]*X[2][0]*X[3][2] + X[1][0]*X[2][3]*X[3][2] + X[1][2]*X[2][0]*X[3][3] - X[1][0]*X[2][2]*X[3][3];
    Y[1][1] = X[0][2]*X[2][3]*X[3][0] - X[0][3]*X[2][2]*X[3][0] + X[0][3]*X[2][0]*X[3][2] - X[0][0]*X[2][3]*X[3][2] - X[0][2]*X[2][0]*X[3][3] + X[0][0]*X[2][2]*X[3][3];
    Y[1][2] = X[0][3]*X[1][2]*X[3][0] - X[0][2]*X[1][3]*X[3][0] - X[0][3]*X[1][0]*X[3][2] + X[0][0]*X[1][3]*X[3][2] + X[0][2]*X[1][0]*X[3][3] - X[0][0]*X[1][2]*X[3][3];
    Y[1][3] = X[0][2]*X[1][3]*X[2][0] - X[0][3]*X[1][2]*X[2][0] + X[0][3]*X[1][0]*X[2][2] - X[0][0]*X[1][3]*X[2][2] - X[0][2]*X[1][0]*X[2][3] + X[0][0]*X[1][2]*X[2][3];
    Y[2][0] = X[1][1]*X[2][3]*X[3][0] - X[1][3]*X[2][1]*X[3][0] + X[1][3]*X[2][0]*X[3][1] - X[1][0]*X[2][3]*X[3][1] - X[1][1]*X[2][0]*X[3][3] + X[1][0]*X[2][1]*X[3][3];
    Y[2][1] = X[0][3]*X[2][1]*X[3][0] - X[0][1]*X[2][3]*X[3][0] - X[0][3]*X[2][0]*X[3][1] + X[0][0]*X[2][3]*X[3][1] + X[0][1]*X[2][0]*X[3][3] - X[0][0]*X[2][1]*X[3][3];
    Y[2][2] = X[0][1]*X[1][3]*X[3][0] - X[0][3]*X[1][1]*X[3][0] + X[0][3]*X[1][0]*X[3][1] - X[0][0]*X[1][3]*X[3][1] - X[0][1]*X[1][0]*X[3][3] + X[0][0]*X[1][1]*X[3][3];
    Y[2][3] = X[0][3]*X[1][1]*X[2][0] - X[0][1]*X[1][3]*X[2][0] - X[0][3]*X[1][0]*X[2][1] + X[0][0]*X[1][3]*X[2][1] + X[0][1]*X[1][0]*X[2][3] - X[0][0]*X[1][1]*X[2][3];
    Y[3][0] = X[1][2]*X[2][1]*X[3][0] - X[1][1]*X[2][2]*X[3][0] - X[1][2]*X[2][0]*X[3][1] + X[1][0]*X[2][2]*X[3][1] + X[1][1]*X[2][0]*X[3][2] - X[1][0]*X[2][1]*X[3][2];
    Y[3][1] = X[0][1]*X[2][2]*X[3][0] - X[0][2]*X[2][1]*X[3][0] + X[0][2]*X[2][0]*X[3][1] - X[0][0]*X[2][2]*X[3][1] - X[0][1]*X[2][0]*X[3][2] + X[0][0]*X[2][1]*X[3][2];
    Y[3][2] = X[0][2]*X[1][1]*X[3][0] - X[0][1]*X[1][2]*X[3][0] - X[0][2]*X[1][0]*X[3][1] + X[0][0]*X[1][2]*X[3][1] + X[0][1]*X[1][0]*X[3][2] - X[0][0]*X[1][1]*X[3][2];
    Y[3][3] = X[0][1]*X[1][2]*X[2][0] - X[0][2]*X[1][1]*X[2][0] + X[0][2]*X[1][0]*X[2][1] - X[0][0]*X[1][2]*X[2][1] - X[0][1]*X[1][0]*X[2][2] + X[0][0]*X[1][1]*X[2][2];

    for (int i=0; i<4; i++)
   	    for (int j=0; j<4; j++)
            Y[i][j] = Y[i][j]/det;
}

void invertMat33(double X[][3], double Y[][3])
{
    double det = X[0][0]* (X[1][1]* X[2][2]- X[2][1]* X[1][2])-
        X[0][1]* (X[1][0]* X[2][2]- X[1][2]* X[2][0])+
        X[0][2]* (X[1][0]* X[2][1]- X[1][1]* X[2][0]);

    double invdet = 1 / det;

    Y[0][0]= (X[1][1]* X[2][2]- X[2][1]* X[1][2]) * invdet;
    Y[0][1]= (X[0][2]* X[2][1]- X[0][1]* X[2][2]) * invdet;
    Y[0][2]= (X[0][1]* X[1][2]- X[0][2]* X[1][1])* invdet;
    Y[1][0]= (X[1][2]* X[2][0]- X[1][0]* X[2][2])* invdet;
    Y[1][1]= (X[0][0]* X[2][2]- X[0][2]* X[2][0])* invdet;
    Y[1][2]= (X[1][0]* X[0][2]- X[0][0]* X[1][2])* invdet;
    Y[2][0]= (X[1][0]* X[2][1]- X[2][0]* X[1][1])* invdet;
    Y[2][1]= (X[2][0]* X[0][1]- X[0][0]* X[2][1])* invdet;
    Y[2][2]= (X[0][0]* X[1][1]- X[1][0]* X[0][1]) * invdet;
}

void subtractVec(double *a, double *b, double *c, int s)
{
    for (int i=0; i<s; i++)
        c[i] = a[i]-b[i];
}

void cross(double *u, double *v, double *w)
{
    w[0] = u[1]*v[2]-u[2]*v[1];
    w[1] = u[2]*v[0]-u[0]*v[2];
    w[2] = u[0]*v[1]-u[1]*v[0];
}

void negateVec(double *a, int s)
{
    for (int i=0; i<s; i++)
        a[i] = -a[i];
}

//s1,s2,s3: fastest to slowest
void sliceImageDouble(double *input, int s1, int s2, int s3, double *output, int indS1)
{
    for (int i=0; i<s3; i++)
        for (int j=0; j<s2; j++)
        {
            output[i*s2+j] = input[i*s2*s1+j*s1+indS1]*input[i*s2*s1+j*s1+s1-1];
        }
}

unsigned char quantizeDouble(double val, double minVal, double maxVal)
{
    return (val-minVal)*255.0/(maxVal-minVal);
}

//3D data, fastest to slowest
void quantizeImageDouble3D(double *input, unsigned char *output, int s0, int s1, int s2)
{
    double maxVal[4];
    maxVal[0] = maxVal[1] = maxVal[2] = maxVal[3] = -(1<<15);
    double minVal[4];
    minVal[0] = minVal[1] = minVal[2] = minVal[3] = ((1<<15) - 1);

    for (int i=0; i<s2; i++)
        for (int j=0; j<s1; j++)
            for (int k=0; k<s0; k++)
            {
                if (input[i*s1*s0+j*s0+k]>maxVal[k])
                    maxVal[k] = input[i*s1*s0+j*s0+k];
                if (input[i*s1*s0+j*s0+k]<minVal[k])
                    minVal[k] = input[i*s1*s0+j*s0+k];
            }

    for (int i=0; i<s2; i++)
        for (int j=0; j<s1; j++)
            for (int k=0; k<s0; k++)
            {
                output[i*s1*s0+j*s0+k] = quantizeDouble(input[i*s1*s0+j*s0+k],minVal[k],maxVal[k]);
            }
}

static const char *vrInfo = ("program for testing CUDA-based volume rendering");

int main(int argc, const char **argv)
{
    setbuf(stdout, NULL);    

    hestOpt *hopt=NULL;
    hestParm *hparm;
    airArray *mop;

    double fr[3], at[3], up[3], nc, fc, fov, light_dir[3], isoval, raystep, refstep, thickness, alphamax, phongKa, phongKd;
    int size[2];
    const char *me = argv[0];
    char *inName, *outName, *outNamePng;
    mop = airMopNew();
    hparm = hestParmNew();
    airMopAdd(mop, hparm, (airMopper)hestParmFree, airMopAlways);
    hparm->noArgsIsNoProblem = true;
    hestOptAdd(&hopt, "i", "nin", airTypeString, 1, 1, &inName, "parab_20_20_80.nrrd",
               "input volume to render");
    hestOptAdd(&hopt, "fr", "from", airTypeDouble, 3, 3, fr, "-50 0 0",
               "look-from point");
    hestOptAdd(&hopt, "at", "at", airTypeDouble, 3, 3, at, "0 0 0",
               "look-at point");
    hestOptAdd(&hopt, "up", "up", airTypeDouble, 3, 3, up, "0 0 1",
               "pseudo-up vector");
    hestOptAdd(&hopt, "nc", "near-clip", airTypeDouble, 1, 1, &nc, "-50",
               "near clipping plane");
    hestOptAdd(&hopt, "fc", "far-clip", airTypeDouble, 1, 1, &fc, "50",
               "far clipping plane");
    hestOptAdd(&hopt, "fov", "FOV", airTypeDouble, 1, 1, &fov, "10",
               "field-of-view");
    hestOptAdd(&hopt, "ldir", "direction", airTypeDouble, 3, 3, light_dir, "-1 0 0",
               "direction towards light");
    hestOptAdd(&hopt, "isize", "sx sy", airTypeInt, 2, 2, size, "200 200",
               "output image sizes");
    hestOptAdd(&hopt, "iso", "iso-value", airTypeDouble, 1, 1, &isoval, "0",
               "iso-value");
    hestOptAdd(&hopt, "step", "ray-step", airTypeDouble, 1, 1, &raystep, "0.1",
               "ray traversing step");
    hestOptAdd(&hopt, "refstep", "ref-step", airTypeDouble, 1, 1, &refstep, "1",
               "ref-step");
    hestOptAdd(&hopt, "thick", "thickness", airTypeDouble, 1, 1, &thickness, "0.5",
               "thickness around iso-value");
    hestOptAdd(&hopt, "alpha", "max-alpha", airTypeDouble, 1, 1, &alphamax, "1",
               "maximum value of alpha");
    hestOptAdd(&hopt, "phongKa", "phong-Ka", airTypeDouble, 1, 1, &phongKa, "0.2",
               "Ka value of Phong shading");
    hestOptAdd(&hopt, "phongKd", "phong-Kd", airTypeDouble, 1, 1, &phongKd, "0.8",
               "Kd value of Phong shading");
    hestOptAdd(&hopt, "o", "output", airTypeString, 1, 1, &outName, "out.nrrd",
               "filename for 4-channel double output");
    hestOptAdd(&hopt, "op", "output", airTypeString, 1, 1, &outNamePng, "out_1.png",
               "filename for 1-channel 8-bit output");
    hestParseOrDie(hopt, argc-1, argv+1, hparm, me, vrInfo,
                   AIR_TRUE, AIR_TRUE, AIR_TRUE);
    airMopAdd(mop, hopt, (airMopper)hestOptFree, airMopAlways);
    airMopAdd(mop, hopt, (airMopper)hestParseFree, airMopAlways);

    Nrrd *nin=nrrdNew();
    airMopAdd(mop, nin, (airMopper)nrrdNix, airMopAlways);
    NrrdIoState *nio=nrrdIoStateNew();
    airMopAdd(mop, nio, (airMopper)nrrdIoStateNix, airMopAlways);
    nio->skipData = AIR_TRUE;
    if (nrrdLoad(nin, inName, nio)) {
        char *err = biffGetDone(NRRD);
        airMopAdd(mop, err, airFree, airMopAlways);
        printf("%s: couldn't read input header:\n%s", argv[0], err);
        airMopError(mop); exit(1);
    }
    printf("data will be %u-D array of %s\n", nin->dim,
           airEnumStr(nrrdType, nin->type));
    if (4 == nin->dim && nrrdTypeShort == nin->type) {
       printf("4D array sizes: %u %u %u %u\n",
              (unsigned int)(nin->axis[0].size),
              (unsigned int)(nin->axis[1].size),
              (unsigned int)(nin->axis[2].size),
              (unsigned int)(nin->axis[3].size));
       /* example allocation */
       short *sdata = (short*)calloc(nin->axis[0].size*nin->axis[1].size
                             *nin->axis[2].size*nin->axis[3].size, sizeof(short));
       nin->data = (void*)sdata;
       printf("pre-allocated data at %p\n", nin->data);
       nio->skipData = AIR_FALSE;
       //nrrdInit(nin);
       if (nrrdLoad(nin, inName, NULL)) {
           char *err = biffGetDone(NRRD);
           airMopAdd(mop, err, airFree, airMopAlways);
           printf("%s: couldn't read input data:\n%s", argv[0], err);
           airMopError(mop); exit(1);
       }
       printf("post nrrdLoad: data at %p\n", nin->data);
    } else {
        fprintf(stderr, "didn't get 4D short array; no data allocated; fix me");
        airMopError(mop); exit(1);
    }

    //process input
    normalize(light_dir,3);

    cudaChannelFormatDesc channelDesc;
   
    channelDesc = cudaCreateChannelDesc<short>();
    /* 2-channel data will have:
       4 == nin->dim
       3 == nin->spaceDim */
    if (4 != nin->dim || 3 != nin->spaceDim) {
        fprintf(stderr, "%s: need 3D array in 4D space, (not %uD in %uD)\n",
		argv[0], nin->dim, nin->spaceDim);
        airMopError(mop); exit(1);
    }

    if (nin->axis[3].size != 2) {
        fprintf(stderr, "%s: need the slowest axis of size 2, (not %uD)\n",
        argv[0], (unsigned int)nin->axis[3].size);
        airMopError(mop); exit(1);
    }

    double mat_trans[4][4];

    mat_trans[3][0] = mat_trans[3][1] = mat_trans[3][2] = 0;
    mat_trans[3][3] = 1;

    int dim[4];
    
    dim[0] = nin->axis[3].size;
    dim[1] = nin->axis[0].size;
    dim[2] = nin->axis[1].size;
    dim[3] = nin->axis[2].size;
    for (int i=0; i<3; i++) {
        for (int j=0; j<3; j++) {
            mat_trans[j][i] = nin->axis[i].spaceDirection[j];
        }
        mat_trans[i][3] = nin->spaceOrigin[i];
    }

    double mat_trans_inv[4][4];
    invertMat44(mat_trans,mat_trans_inv);

    double vb0[4] = {0,0,0,1};
    double vb1[4] = {1,0,0,1};
    double vb2[4] = {0,1,0,1};
    double vb3[4] = {0,0,1,1};
    double ve0[4],ve1[4],ve2[4],ve3[4];
    mulMatPoint(mat_trans,vb0,ve0);
    mulMatPoint(mat_trans,vb1,ve1);
    mulMatPoint(mat_trans,vb2,ve2);
    mulMatPoint(mat_trans,vb3,ve3);
    subtractVec(ve1,ve0,ve1,3);
    subtractVec(ve2,ve0,ve2,3);
    subtractVec(ve3,ve0,ve3,3);

    double MT_BE[3][3];
    MT_BE[0][0] = dotProduct(vb1,ve1,3);
    MT_BE[0][1] = dotProduct(vb2,ve1,3);
    MT_BE[0][2] = dotProduct(vb3,ve1,3);
    MT_BE[1][0] = dotProduct(vb1,ve2,3);
    MT_BE[1][1] = dotProduct(vb2,ve2,3);
    MT_BE[1][2] = dotProduct(vb3,ve2,3);
    MT_BE[2][0] = dotProduct(vb1,ve3,3);
    MT_BE[2][1] = dotProduct(vb2,ve3,3);
    MT_BE[2][2] = dotProduct(vb3,ve3,3);

    double MT_BE_inv[3][3];
    invertMat33(MT_BE,MT_BE_inv);

    //tex3D stuff
    const cudaExtent volumeSize = make_cudaExtent(dim[1], dim[2], dim[3]);

    //cudaChannelFormatDesc channelDesc = cudaCreateChannelDesc<float>();
    cudaMalloc3DArray(&d_volumeArray0, &channelDesc, volumeSize);
    cudaMalloc3DArray(&d_volumeArray1, &channelDesc, volumeSize);

    // --- Copy data to 3D array (host to device)
    cudaMemcpy3DParms copyParams1 = {0};
    copyParams1.srcPtr   = make_cudaPitchedPtr((void*)(((short*)nin->data)+dim[1]*dim[2]*dim[3]), volumeSize.width*sizeof(short), volumeSize.width, volumeSize.height);
    copyParams1.dstArray = d_volumeArray1;
    copyParams1.extent   = volumeSize;
    copyParams1.kind     = cudaMemcpyHostToDevice;
    cudaMemcpy3D(&copyParams1);

    cudaMemcpy3DParms copyParams0 = {0};
    copyParams0.srcPtr   = make_cudaPitchedPtr((void*)((short*)nin->data), volumeSize.width*sizeof(short), volumeSize.width, volumeSize.height);
    copyParams0.dstArray = d_volumeArray0;
    copyParams0.extent   = volumeSize;
    copyParams0.kind     = cudaMemcpyHostToDevice;
    cudaMemcpy3D(&copyParams0);
    // --- Set texture parameters
    tex1.normalized = false;                      // access with normalized texture coordinates
    tex1.filterMode = cudaFilterModeLinear;      // linear interpolation
    tex1.addressMode[0] = cudaAddressModeWrap;   // wrap texture coordinates
    tex1.addressMode[1] = cudaAddressModeWrap;
    tex1.addressMode[2] = cudaAddressModeWrap;

    tex0.normalized = false;                      // access with normalized texture coordinates
    tex0.filterMode = cudaFilterModeLinear;      // linear interpolation
    tex0.addressMode[0] = cudaAddressModeWrap;   // wrap texture coordinates
    tex0.addressMode[1] = cudaAddressModeWrap;
    tex0.addressMode[2] = cudaAddressModeWrap;
    // --- Bind array to 3D texture
    cudaBindTextureToArray(tex1, d_volumeArray1, channelDesc);
    cudaBindTextureToArray(tex0, d_volumeArray0, channelDesc);
    //-----------

    normalize(up,3);

    double viewdir[3];
    subtractVec(at,fr,viewdir,3);
    double viewdis = lenVec(viewdir,3);
    double ver_extent = 2*viewdis*tan((fov/2)*PI/180);
    double hor_extent = (ver_extent/size[1])*size[0];
    normalize(viewdir,3);

    double nviewdir[3];
    memcpy(nviewdir,viewdir,sizeof(viewdir));
    negateVec(nviewdir,3);

    double right[3];
    cross(up,nviewdir,right);
    normalize(right,3);

    //correcting the up vector
    cross(nviewdir,right,up);
    normalize(up,3);

    double center[3];
    advancePoint(at,viewdir,nc,center);

    int nOutChannel = 4;

    double *imageDouble = new double[size[0]*size[1]*nOutChannel];

    //CUDA Var

    int *d_dim;
    cudaMalloc(&d_dim, sizeof(dim));
    cudaMemcpy(d_dim, dim, 4*sizeof(int), cudaMemcpyHostToDevice);

    double *d_imageDouble;
    cudaMalloc(&d_imageDouble,sizeof(double)*size[0]*size[1]*nOutChannel);

    int *d_size;
    cudaMalloc(&d_size,2*sizeof(int));
    cudaMemcpy(d_size,size,2*sizeof(int), cudaMemcpyHostToDevice);

    double *d_center;
    cudaMalloc(&d_center,3*sizeof(double));
    cudaMemcpy(d_center,center,3*sizeof(double), cudaMemcpyHostToDevice);

    double *d_viewdir;
    cudaMalloc(&d_viewdir,3*sizeof(double));
    cudaMemcpy(d_viewdir,viewdir,3*sizeof(double), cudaMemcpyHostToDevice);

    double *d_up;
    cudaMalloc(&d_up,3*sizeof(double));
    cudaMemcpy(d_up,up,3*sizeof(double), cudaMemcpyHostToDevice);

    double *d_right;
    cudaMalloc(&d_right,3*sizeof(double));
    cudaMemcpy(d_right,right,3*sizeof(double), cudaMemcpyHostToDevice);

    double *d_light_dir;
    cudaMalloc(&d_light_dir,3*sizeof(double));
    cudaMemcpy(d_light_dir,light_dir,3*sizeof(double), cudaMemcpyHostToDevice);

    double* d_mat_trans;
    cudaMalloc(&d_mat_trans,16*sizeof(double));
    cudaMemcpy(d_mat_trans,&mat_trans[0][0],16*sizeof(double), cudaMemcpyHostToDevice);

    double* d_MT_BE_inv;
    cudaMalloc(&d_MT_BE_inv,9*sizeof(double));
    cudaMemcpy(d_MT_BE_inv,&MT_BE_inv[0][0],9*sizeof(double), cudaMemcpyHostToDevice);

    double* d_mat_trans_inv;
    cudaMalloc(&d_mat_trans_inv,16*sizeof(double));
    cudaMemcpy(d_mat_trans_inv,&mat_trans_inv[0][0],16*sizeof(double), cudaMemcpyHostToDevice);

    int numThread1D = 16;
    dim3 threadsPerBlock(numThread1D,numThread1D);
    dim3 numBlocks((size[0]+numThread1D-1)/numThread1D,(size[1]+numThread1D-1)/numThread1D);

    kernel<<<numBlocks,threadsPerBlock>>>(d_dim, d_size, hor_extent, ver_extent,
                                          d_center, d_viewdir, d_right, d_up, d_light_dir, nc, fc, raystep, refstep, d_mat_trans,
                                          d_mat_trans_inv, d_MT_BE_inv, phongKa, phongKd, isoval, alphamax, thickness, nOutChannel, d_imageDouble                                          
                                          );
    
    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) 
        printf("Error: %s\n", cudaGetErrorString(err));

    err = cudaDeviceSynchronize();
    if (err != cudaSuccess) 
        printf("Error Sync: %s\n", cudaGetErrorString(err));

    cudaMemcpy(imageDouble, d_imageDouble, sizeof(double)*size[0]*size[1]*nOutChannel, cudaMemcpyDeviceToHost);

    short width = size[0];
    short height = size[1];

    double *imageSave = new double[size[0]*size[1]];
    unsigned char *imageQuantized = new unsigned char[size[0]*size[1]*4];
    quantizeImageDouble3D(imageDouble,imageQuantized,4,size[0],size[1]);
    sliceImageDouble(imageDouble,4,size[0],size[1],imageSave,3);

    Nrrd *nout = nrrdNew();
    Nrrd *ndbl = nrrdNew();
    Nrrd *ndbl_1 = nrrdNew();
    airMopAdd(mop, nout, (airMopper)nrrdNuke, airMopAlways);
    airMopAdd(mop, ndbl, (airMopper)nrrdNix, airMopAlways);
    airMopAdd(mop, ndbl_1, (airMopper)nrrdNix, airMopAlways);

    //printf("before saving result\n");  
    if (nrrdWrap_va(ndbl, imageDouble, nrrdTypeDouble, 3,
                    static_cast<size_t>(4),
                    static_cast<size_t>(width),
                    static_cast<size_t>(height))
        || nrrdSave(outName,ndbl,NULL)
        || nrrdWrap_va(ndbl_1, imageSave, nrrdTypeDouble, 2,
                       static_cast<size_t>(width),
                       static_cast<size_t>(height))
        || nrrdQuantize(nout, ndbl_1, NULL, 8)
        || nrrdSave(outNamePng, nout, NULL)       
        ) {
        char *err = biffGetDone(NRRD);
        airMopAdd(mop, err, airFree, airMopAlways);
        printf("%s: couldn't save output:\n%s", argv[0], err);
        airMopError(mop); exit(1);
    }

    airMopOkay(mop);


    TGAImage *img = new TGAImage(width,height);
    
    //declare a temporary color variable
    Colour c;
    
    //Loop through image and set all pixels to red
    for(int x=0; x<height; x++)
        for(int y=0; y<width; y++)
        {
            c.r = imageQuantized[x*width*4+y*4];
            c.g = imageQuantized[x*width*4+y*4+1];
            c.b = imageQuantized[x*width*4+y*4+2];
            c.a = imageQuantized[x*width*4+y*4+3];
            img->setPixel(c,x,y);
        }
    
    //write the image to disk
    string imagename = "test_short.tga";
    img->WriteImage(imagename);

    for (int k=0; k<4; k++)
    {
        //Loop through image and set all pixels to red
        for(int x=0; x<height; x++)
            for(int y=0; y<width; y++)
            {
                c.r = c.g = c.b = 0;
                c.a = 255;
                switch (k)
                {
                    case 0:
                        c.r = imageQuantized[x*width*4+y*4];            
                        break;
                    case 1:
                        c.g = imageQuantized[x*width*4+y*4+1];
                        break;
                    case 2:
                        c.b = imageQuantized[x*width*4+y*4+2];
                        break;
                    case 3:
                        c.a = imageQuantized[x*width*4+y*4+3];
                        break;
                }                

                img->setPixel(c,x,y);
            }
        
        //write the image to disk
        ostringstream ss;
        ss << k;
        string imagename = "test_short_"+ss.str()+".tga";
        img->WriteImage(imagename);    
    }
    delete img;
    
    //cleaning up
    delete[] imageDouble;
    delete[] imageSave;
    cudaFreeArray(d_volumeArray1);
    cudaFreeArray(d_volumeArray0);
    cudaFree(d_size);
    cudaFree(d_right);
    cudaFree(d_up);
    cudaFree(d_viewdir);
    cudaFree(d_center);
    cudaFree(d_dim);
    cudaFree(d_imageDouble);
    cudaFree(d_mat_trans);
    cudaFree(d_light_dir);
    cudaFree(d_mat_trans_inv);
    cudaFree(d_MT_BE_inv);    

    return 0;
}

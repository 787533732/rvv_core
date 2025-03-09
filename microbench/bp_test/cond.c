#include <stdio.h>
void main() {
  int i,j,k,l,m,n,o,p=0,q=1,r=2,s=3,t=4,u=5;
  for (i=0;i<1000;i++) {
    j = i%2;
    if (j==0)
	p++;
    else
	r++;
  }
  //printf("p r %d %d\n",p,r);
}

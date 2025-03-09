#include "stdio.h"
/* dependent loads */
void main() {
  int a[8192], b;
  int i,j=1, k=2, l=3, m=4, n=5, o=6, p=7,r;
  for (i=0;i<8192;i++) {
    a[i] = i;
  }
  for (r=0;r<1500;r++) {
    for (i=0;i<8191;i++) {
      j=a[i]+j;
    }
  }
  printf("j k l m n o p %d %d %d %d %d %d %d\n",j,k,l,m,n,o,p);
}


#include <stdio.h>
void main() {
  int i,j, k=1, l=2, m=3, n=4, o=5;
  for (i=0;i<4000;i++) {
    j=i%10;
    switch (j) {
      case 0:
	k++;
	break;
      case 1:
	l++;
	break;
      case 3:
	m++;
	break;
      case 4:
	n++;
	break;
      case 5:
	o++;
	break;
      case 6:
	k--;
	break;
      case 7:
        l--;
	break;
      case 8:
	m--;
	break;
      case 9:
	n--;
	break;
      case 2:
	o--;
    }
  }
  //printf("k l m n o %d %d %d %d %d\n",k,l,m,n,o);
}

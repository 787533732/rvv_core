#include <stdio.h>
void main() {
  int i,j, k=1, l=2, m=3, n=4, o=5;
  for (i=0;i<4000000;i++) {
    j=i%20;
    switch (j) {
      case 0:
      case 1:
	k++;
	break;
      case 2:
      case 3:
	l++;
	break;
      case 4:
      case 5:
	m++;
	break;
      case 6:
      case 7:
	n++;
	break;
      case 8:
      case 9:
	o++;
	break;
      case 10:
      case 11:
	k--;
	break;
      case 12:
      case 13:
        l--;
	break;
      case 14:
      case 15:
	m--;
	break;
      case 16:
      case 17:
	n--;
	break;
      case 18:
      case 19:
	o--;
    }
  }
  printf("k l m n o %d %d %d %d %d\n",k,l,m,n,o);
}

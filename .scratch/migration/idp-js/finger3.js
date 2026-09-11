
function getFinger3(){

    try {
        localstorageUtil.getFinger3FromLocal().then(function (finger3){
            if(finger3 !== null && finger3 !== undefined){
                $("#fingerGenPrint3").val(finger3);
            }else{
                localstorageUtil.getFinger3FromRemoteAndSave().then(function (finger3){
                    $("#fingerGenPrint3").val(finger3);
                });
            }
        });
    } catch (error) {
        console.log('getFinger3 error');
    }

}
getFinger3();

//默认是yes
localstorageUtil.getSingleLoginKey().then(function (res){
    if(res === "yes"){
        $('input[name="singleLogin"]').prop("checked",true);
    }else{
        $('input[name="singleLogin"]').prop("checked",false);
    }
});
$('input[name="singleLogin"]').change(function() {
    // 判断复选框是否被选中
    if ($(this).is(':checked')) {
        localstorageUtil.setSingleLoginKey("yes");
    } else {
        localstorageUtil.setSingleLoginKey("no");
    }
});

